#!/usr/bin/env python3
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
REPO = 'example-org/example-repo'
OTHER = 'example-org/other-docs'
CONFIG = {'docs': {REPO: ['README.md', 'docs/'], OTHER: ['README.md']},
          'help': {'widget': [REPO, 'help.json']}}


def fake_gh():
    _, _, command, *args = sys.argv
    assert command == 'api' and args[:2] == ['--hostname', 'github.com'], args
    method, endpoint = args[3:5]
    assert args[2] == '--method', args
    repo, route = re.fullmatch(r'repos/([^/]+/[^/]+)/(.*)', endpoint).groups()
    fixture = Path(os.environ['FIXTURE'])
    state = json.loads(fixture.read_text())
    source = state['sources'][repo]
    issues = source['issues']
    if route == source.get('fail_read') and method == 'GET':
        sys.exit(1)
    if route == source.get('fail_close') and method == 'PATCH':
        sys.exit(1)
    if method == 'GET' and route.startswith('tarball/'):
        assert route == 'tarball/' + source['sha'], route
        with tarfile.open(fileobj=sys.stdout.buffer, mode='w|gz') as archive:
            for path, text in source['files'].items():
                data = text.encode()
                member = tarfile.TarInfo('example-snapshot/' + path)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
        return
    if method == 'GET':
        if route == 'git/ref/heads/main':
            output = {'object': {'sha': source['sha']}}
        elif route == 'issues?state=all&per_page=100':
            assert args[5:] == ['--paginate', '--slurp']
            output = [[], issues]
        else:
            number = int(re.fullmatch(r'issues/(\d+)/comments\?per_page=100', route)[1])
            output = [source['comments'].get(str(number), [])]
    else:
        assert args[5:] == ['--input', '-'], args
        body = json.load(sys.stdin)
        state['writes'].append([repo, method, route, body])
        if method == 'POST' and route == 'issues':
            issue = dict(body, number=max(i['number'] for i in issues) + 1, state='open')
            issues.append(issue)
            output = issue
        elif method == 'POST':
            number = re.fullmatch(r'issues/(\d+)/comments', route)[1]
            source['comments'].setdefault(number, []).append(body)
            output = body
        else:
            assert method == 'PATCH' and body == {'state': 'closed'}, (method, body)
            number = int(re.fullmatch(r'issues/(\d+)', route)[1])
            output = next(i for i in issues if i['number'] == number)
            output.update(body)
        fixture.write_text(json.dumps(state))
    print(json.dumps(output))


class DocsTruth(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.work = Path(temp.name)
        self.fixture = self.work / 'fixture.json'
        files = {
            'README.md': 'Run `widget removed` and read `docs/missing.md`. See contract `gone.v1`.\n'
                         'Use `widget show <id>` then read [this page](docs/start.md#intro).\n'
                         'See `contracts/live.v1.md` and the `live.v1` contract.\n'
                         'The `.json` suffix and `example.py` basename are examples. Fetch tag `docs/v0.1.0`.\n'
                         'A reference is [record](<full pointer URL>). `widget old` was retired.\n'
                         'See `docs/private.md` in the private checkout.\n'
                         '```sh\nwidget not-prose\n```\n',
            'docs/start.md': 'See [README](../README.md), [external](https://example.com/) and '
                             '`docs/missing.md`. Run `widget removed` again.\n'
                             'An example: `widget $(touch marker)`.\n',
            'contracts/live.v1.md': '# A contract\n',
            'help.json': json.dumps({'commands': [{'argv': ['show'], 'aliases': [['ls']], 'arguments': [1]}]}),
        }
        self.save({'sources': {REPO: self.source(files), OTHER: self.source({'README.md': 'Run `widget ls`.\n'})},
                   'writes': []})
        fake = self.work / 'gh'
        fake.write_text('#!/bin/sh\nexec "$TEST_PYTHON" -I "$TEST_SCRIPT" fake "$@"\n')
        fake.chmod(0o700)
        self.env = {'PATH': str(self.work) + os.pathsep + os.environ['PATH'], 'FIXTURE': str(self.fixture),
                    'TEST_PYTHON': sys.executable, 'TEST_SCRIPT': str(Path(__file__).resolve()),
                    'WIZLOOP_PARAM_SOURCES': json.dumps(CONFIG)}

    def source(self, files):
        return {'sha': '1' * 40, 'files': files, 'comments': {},
                'issues': [{'number': 1, 'title': 'Docs drift [docs-truth:' + 'a' * 64 + ']',
                            'state': 'open', 'body': 'A separate issue.'},
                           {'number': 2, 'title': 'A review', 'state': 'open', 'pull_request': {}, 'body': ''}]}

    def load(self):
        return json.loads(self.fixture.read_text())

    def save(self, data):
        self.fixture.write_text(json.dumps(data))

    def check(self, code=0):
        run = subprocess.run(['sh', str(HERE / 'check.sh')], cwd=self.work, env=self.env,
                             text=True, capture_output=True, timeout=15)
        self.assertEqual(run.returncode, code, run.stderr)
        self.assertEqual(run.stdout, '')
        self.assertFalse((self.work / 'marker').exists())
        return self.load()

    def test_three_drifts_deduplicate_and_close_only_after_a_fix(self):
        written = self.check()['writes']
        self.assertEqual(len(written), 3, written)
        bodies = {next(name for name in ('widget removed', 'docs/missing.md', 'gone.v1') if name in body['body']):
                  body['title'] for repo, method, route, body in written
                  if (repo, method, route) == (REPO, 'POST', 'issues')}
        self.assertEqual(len(bodies), 3)
        self.assertEqual(len(set(bodies.values())), 3)
        self.assertEqual(self.check()['writes'], written)
        fixed = self.load()
        source = fixed['sources'][REPO]
        source['sha'] = '2' * 40
        source['files']['docs/missing.md'] = 'The path has been restored.\n'
        number = next(i['number'] for i in source['issues'] if i['title'] == bodies['docs/missing.md'])
        self.save(fixed)
        fixed = self.check()
        changes = fixed['writes'][3:]
        self.assertEqual([row[:3] for row in changes],
                         [[REPO, 'POST', 'issues/%d/comments' % number], [REPO, 'PATCH', 'issues/%d' % number]])
        self.assertIn('2' * 40, changes[0][3]['body'])
        self.assertEqual(self.check()['writes'], fixed['writes'])

    def test_an_incomplete_snapshot_prevents_every_issue_write(self):
        state = self.load()
        state['sources'][OTHER]['fail_read'] = 'tarball/' + '1' * 40
        self.save(state)
        self.assertEqual(self.check(code=2)['writes'], [])

    def test_the_rendered_loop_runs_from_an_empty_folder(self):
        rendered = self.work / 'rendered.sh'
        params = json.dumps({'sources': json.dumps(CONFIG)})
        subprocess.run(['sh', '-c', '. "$1"; render_check "$2" "$3" "$4"', 'render',
                        str(HERE.parent / 'test-params.sh'), str(HERE.parent / 'docs-truth.md'),
                        str(rendered), params], cwd=self.work, env=self.env, check=True)
        env = dict(self.env)
        del env['WIZLOOP_PARAM_SOURCES']
        run = subprocess.run(['sh', str(rendered)], cwd=self.work, env=env,
                             capture_output=True, text=True, timeout=15)
        self.assertEqual((run.returncode, run.stdout), (0, ''), run.stderr)
        self.assertEqual(len(self.load()['writes']), 3)

    def test_disabling_a_help_source_does_not_close_its_unchecked_drift(self):
        already = self.check()['writes']
        self.env['WIZLOOP_PARAM_SOURCES'] = json.dumps(dict(CONFIG, help={}))
        self.assertEqual(self.check()['writes'], already)

    def test_an_existing_title_still_deduplicates_after_an_issue_body_edit(self):
        state = self.check()
        issues = state['sources'][REPO]['issues']
        next(i for i in issues if 'widget removed' in i['body'])['body'] = 'An edited report.'
        self.save(state)
        self.assertEqual(self.check()['writes'], state['writes'])

    def test_retries_a_failed_close_without_posting_the_comment_twice(self):
        initial = self.check()
        repo = initial['sources'][REPO]
        issue = next(i for i in repo['issues'] if 'gone.v1' in i['body'])
        route = 'issues/%d' % issue['number']
        repo['files']['contracts/gone.v1.md'] = '# Restored\n'
        repo['fail_close'] = route
        self.save(initial)
        after_comment = self.check(code=2)
        self.assertEqual([row[1:3] for row in after_comment['writes'][3:]], [['POST', route + '/comments']])
        del after_comment['sources'][REPO]['fail_close']
        self.save(after_comment)
        self.assertEqual([row[1:3] for row in self.check()['writes'][3:]],
                         [['POST', route + '/comments'], ['PATCH', route]])


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'fake':
        fake_gh()
    else:
        unittest.main()
