#!/bin/sh
exec python3 -I - <<'PY'
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import os
import posixpath
import re
import subprocess
import sys
import tarfile
import time
from urllib.parse import quote, unquote

REPO = re.compile(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+')
PATH = re.compile(r'[A-Za-z0-9._/-]+')
WORD = re.compile(r'[a-z][a-z0-9_-]*')
SHA = re.compile(r'[0-9a-f]{40}')
TITLE = re.compile(r'Docs drift \[docs-truth:([0-9a-f]{64})\]')
CONTRACT = re.compile(r'[a-z][a-z0-9_.-]*\.v[0-9]+')
VERSIONED_FILE = re.compile(r'(.+\.v[0-9]+)(?:\.md|\.schema\.json)')
FENCE = re.compile(r'^[ \t]*(?P<token>`{3,}|~{3,})(?P<info>.*)$')
DESTINATION = r'(?:<([^<>\n]+)>|([^\s<>)]+))'
LINK = re.compile(r'!?\[[^\]\n]*\]\(\s*' + DESTINATION + r'''(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)''')
LINK_DEF = re.compile(r'^\s*\[[^\]]+\]:\s*' + DESTINATION)
CODE = re.compile(r'(?<!`)(`+)([^`]+?)\1(?!`)')
PATH_CONTEXT = re.compile(r'\b(?:path|file|directory|folder)\s*:?\s*$', re.I)
TAG = re.compile(r'v?\d+(?:\.\d+)+(?:[-+][A-Za-z0-9.-]+)?')
OTHER_CHECKOUT = re.compile(r'^\s+in (?:the )?(?:private|another) (?:checkout|repository)\b', re.I)
RETIRED = re.compile(r'^\s+(?:is|was|has been) (?:removed|retired|renamed)\b', re.I)
MARKER = '<!-- wizloops:docs-truth:v1:%s -->'
FIXED = '<!-- wizloops:docs-truth:fixed:%s -->'


class Refused(Exception):
    pass


def repo_name(value):
    return isinstance(value, str) and REPO.fullmatch(value) and value.rsplit('/', 1)[1] not in ('.', '..')


def safe_path(value):
    return (isinstance(value, str) and PATH.fullmatch(value)
            and all(part not in ('', '.', '..') for part in value.rstrip('/').split('/')))


def config():
    value = json.loads(os.environ['WIZLOOP_PARAM_SOURCES'])
    if not isinstance(value, dict) or set(value) != {'docs', 'help'}:
        raise Refused('sources must configure docs and help')
    docs, help_sources = value['docs'], value['help']
    if not isinstance(docs, dict) or not docs or not isinstance(help_sources, dict):
        raise Refused('configure at least one docs source and a help map')
    if (not all(repo_name(repo) and isinstance(paths, list) and paths
                and all(safe_path(path) and path.endswith(('.md', '/')) for path in paths)
                for repo, paths in docs.items())
            or not all(WORD.fullmatch(tool) and isinstance(source, list) and len(source) == 2
                       and repo_name(source[0]) and safe_path(source[1]) and source[1].endswith('.json')
                       for tool, source in help_sources.items())):
        raise Refused('invalid docs selectors or help source')
    names = {repo.lower(): repo for repo in docs}
    if len(names) != len(docs):
        raise Refused('a docs repository is listed twice')
    return docs, {tool: (names.get(repo.lower(), repo), path) for tool, (repo, path) in help_sources.items()}


class GitHub:
    def __init__(self):
        self.deadline = time.monotonic() + 52

    def api(self, repo, route, method='GET', body=None, paginate=False):
        args = ['gh', 'api', '--hostname', 'github.com', '--method', method, 'repos/' + repo + '/' + route]
        if paginate:
            args += ['--paginate', '--slurp']
        if body is not None:
            args += ['--input', '-']
        seconds = self.deadline - time.monotonic()
        if seconds <= 0:
            raise Refused('the check ran out of time')
        try:
            result = subprocess.run(args, input=json.dumps(body).encode() if body is not None else b'',
                                    capture_output=True, timeout=seconds, check=True)
        except (OSError, subprocess.SubprocessError):
            raise Refused('GitHub did not confirm %s %s/%s' % (method, repo, route)) from None
        return result.stdout

    def pages(self, repo, route):
        pages = json.loads(self.api(repo, route, paginate=True))
        if not isinstance(pages, list) or not pages or not all(isinstance(page, list) for page in pages):
            raise Refused('GitHub returned an invalid page for ' + repo)
        return [row for page in pages for row in page]


def selected(path, selectors):
    return any(path.startswith(selector) if selector.endswith('/') else selector == path for selector in selectors)


def snapshot(github, repo, selectors, help_paths):
    sha = json.loads(github.api(repo, 'git/ref/heads/main'))['object']['sha']
    if not isinstance(sha, str) or not SHA.fullmatch(sha):
        raise Refused('GitHub did not identify main for ' + repo)
    data = github.api(repo, 'tarball/' + sha)
    paths = {''}
    text = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for entry in archive:
            _, _, path = entry.name.partition('/')
            path = path.rstrip('/')
            if not safe_path(path):
                continue
            paths.add(path)
            paths.update('/'.join(path.split('/')[:i]) for i in range(1, path.count('/') + 1))
            if path in help_paths or (path.endswith('.md') and selected(path, selectors)):
                if not entry.isfile():
                    raise Refused('a docs or help input is not a file in ' + repo)
                text[path] = archive.extractfile(entry).read().decode('utf-8')
    if not text.keys() >= help_paths:
        raise Refused('a help catalogue is missing on main in ' + repo)
    return sha, paths, text


def command_words(tokens):
    result = []
    for token in tokens:
        if not WORD.fullmatch(token):
            break
        result.append(token)
    return tuple(result)


def commands(data):
    rows = json.loads(data)['commands']
    if not isinstance(rows, list):
        raise Refused('a help catalogue has no command list')
    forms = {}
    for row in rows:
        for argv in [row['argv'], *row.get('aliases', [])]:
            if not isinstance(argv, list) or not argv or not all(isinstance(word, str) for word in argv):
                raise Refused('a help catalogue has an invalid command')
            form = command_words(argv)
            if form:
                forms[form] = forms.get(form, False) or bool(row.get('arguments'))
    return forms


def command_exists(words, forms):
    return (any(form[:len(words)] == words for form in forms)
            or any(takes_args and words[:len(form)] == form for form, takes_args in forms.items()))


def prose(text):
    fence = ''
    for number, line in enumerate(text.splitlines(), 1):
        match = FENCE.match(line)
        if match:
            token, info = match['token'], match['info']
            if not fence:
                fence = token
                continue
            if token.startswith(fence) and not info.strip():
                fence = ''
        if not fence and not line.startswith(('    ', '\t')):
            yield number, line


def local_path(raw, parent):
    raw = unquote(raw.partition('#')[0].partition('?')[0])
    if not raw or raw.startswith('/') or not PATH.fullmatch(raw):
        return None
    path = posixpath.normpath(posixpath.join(parent, raw))
    if path == '.':
        return ''
    return path if safe_path(path) else None


def path_kind(path):
    return 'contract' if path.startswith('contracts/') or VERSIONED_FILE.fullmatch(posixpath.basename(path)) else 'path'


def inline_path(value, parent, before, paths):
    explicit = PATH_CONTEXT.search(before)
    if not explicit and (value.startswith('.') and '/' not in value or TAG.fullmatch(value.rsplit('/', 1)[-1])):
        return None
    path = local_path(value, parent if value.startswith('../') else '')
    if path is None:
        return None
    if explicit and '/' not in value and local_path(value, parent) in paths:
        return local_path(value, parent)
    if explicit or value.startswith(('./', '../')) or ('/' in value and path.partition('/')[0] in paths):
        return path
    return None


def drifts(paths, text, selectors, help_forms):
    contracts = {match[1] for path in paths if (match := VERSIONED_FILE.fullmatch(posixpath.basename(path)))}
    absent = {}
    for doc in sorted(path for path in text if path.endswith('.md') and selected(path, selectors)):
        parent = posixpath.dirname(doc)
        for number, line in prose(text[doc]):
            links = list(LINK.finditer(line))
            definition = LINK_DEF.match(line)
            for link in links + ([definition] if definition else []):
                path = local_path(link[1] or link[2], parent)
                if path is not None and path not in paths:
                    absent.setdefault((path_kind(path), path), (doc, number))
            unlinked = LINK.sub('', line)
            for match in CODE.finditer(unlinked):
                value = match[2].strip()
                before, after = unlinked[:match.start()], unlinked[match.end():]
                if OTHER_CHECKOUT.match(after) or RETIRED.match(after):
                    continue
                words = value.split()
                if words and words[0] in help_forms:
                    tool, subcommands = words[0], command_words(words[1:])
                    if subcommands and 'usage error' not in before and not command_exists(subcommands, help_forms[tool]):
                        absent.setdefault(('command', ' '.join((tool, *subcommands))), (doc, number))
                elif CONTRACT.fullmatch(value) and re.search(r'\bcontract\b', line, re.I):
                    if value not in contracts and value.partition('.')[2] not in contracts:
                        absent.setdefault(('contract', value), (doc, number))
                else:
                    path = inline_path(value, parent, before, paths)
                    if path is not None and path not in paths:
                        absent.setdefault((path_kind(path), path), (doc, number))
    return absent


def key_for(kind, target):
    return hashlib.sha256((kind + '\n' + target).encode()).hexdigest()


def issue_body(key, kind, target, doc, number, repo, sha):
    url = 'https://github.com/%s/blob/%s/%s#L%d' % (repo, sha, quote(doc, safe='/'), number)
    return ('%s\nSee [%s](%s). The documented %s `%s` was not found at this main commit.\n' %
            (MARKER % key, doc, url, kind, target))


def issue_plan(github, repo, selectors, sha, absent, help_forms):
    listed = set()
    managed = {}
    for issue in github.pages(repo, 'issues?state=all&per_page=100'):
        if (not isinstance(issue, dict) or type(issue.get('number')) is not int or issue['number'] < 1
                or not isinstance(issue.get('title'), str) or issue.get('state') not in ('open', 'closed')):
            raise Refused('GitHub returned an invalid issue for ' + repo)
        match = TITLE.fullmatch(issue['title'])
        if not match or 'pull_request' in issue:
            continue
        key = match[1]
        listed.add(key)
        body = issue.get('body')
        if not isinstance(body, str) or not body.startswith(MARKER % key + '\n'):
            continue
        evidence = re.fullmatch(re.escape(MARKER % key) + r'\nSee \[[^\]\n]+\]\(https://github\.com/'
                                + '(?i:' + re.escape(repo) + r')/blob/[0-9a-f]{40}/([^#)]+)#L[0-9]+\)\. '
                                r'The documented (command|contract|path) `([^`\n]+)` was not found at this main commit\.\n',
                                body)
        if not evidence or not safe_path(unquote(evidence[1])) or key_for(evidence[2], evidence[3]) != key:
            continue
        if key in managed:
            raise Refused('an ambiguous docs-truth issue in ' + repo)
        managed[key] = issue, unquote(evidence[1]), evidence[2], evidence[3]
    current = set()
    plan = []
    for (kind, target), (doc, number) in sorted(absent.items()):
        key = key_for(kind, target)
        current.add(key)
        if key not in listed:
            body = issue_body(key, kind, target, doc, number, repo, sha)
            plan.append(('POST', 'issues', {'title': 'Docs drift [docs-truth:%s]' % key, 'body': body}))
    for key, (issue, source, kind, target) in managed.items():
        if key in current or issue['state'] != 'open' or not selected(source, selectors):
            continue
        if kind == 'command' and target.split()[0] not in help_forms:
            continue
        route = 'issues/%d' % issue['number']
        marker = FIXED % key
        comments = github.pages(repo, route + '/comments?per_page=100')
        if not all(isinstance(comment, dict) and isinstance(comment.get('body'), str) for comment in comments):
            raise Refused('GitHub returned an invalid comment for ' + repo)
        if not any(comment['body'].startswith(marker + '\n') for comment in comments):
            body = marker + '\nThe docs-truth check found this drift resolved at main commit `%s`.\n' % sha
            plan.append(('POST', route + '/comments', {'body': body}))
        plan.append(('PATCH', route, {'state': 'closed'}))
    return plan


def main():
    docs, help_sources = config()
    github = GitHub()
    repos = sorted(docs.keys() | {repo for repo, _ in help_sources.values()})
    with ThreadPoolExecutor(max_workers=4) as pool:
        reads = {repo: pool.submit(snapshot, github, repo, docs.get(repo, ()),
                                   {path for origin, path in help_sources.values() if origin == repo}) for repo in repos}
        snapshots = {repo: read.result() for repo, read in reads.items()}
        help_forms = {tool: commands(snapshots[repo][2][path]) for tool, (repo, path) in help_sources.items()}
        scans = {}
        for repo, selectors in docs.items():
            sha, paths, text = snapshots[repo]
            absent = drifts(paths, text, selectors, help_forms)
            scans[repo] = pool.submit(issue_plan, github, repo, selectors, sha, absent, help_forms)
        plans = {repo: scan.result() for repo, scan in scans.items()}
    for repo, plan in plans.items():
        for method, route, body in plan:
            github.api(repo, route, method, body)


try:
    main()
except Refused as error:
    print('docs-truth: ' + str(error), file=sys.stderr)
    sys.exit(2)
except (KeyError, ValueError, TypeError, AttributeError, OSError, tarfile.TarError):
    print('docs-truth: incomplete or unreadable input', file=sys.stderr)
    sys.exit(2)
PY
