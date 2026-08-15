#!/usr/bin/env python3
"""Small TOML-aware, atomic edits used by Windows installer."""
import base64, os, re, sys, tempfile, tomllib


def parse(path):
    with open(path, 'rb') as f:
        return tomllib.load(f)


def atomic(path, text):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or '.', prefix='.toml-', text=True)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except FileNotFoundError: pass
        raise


def headers(text):
    out, mode, pos = [], None, 0
    for line in text.splitlines(True):
        if mode is None:
            m = re.match(r'\s*(\[\[?[^\r\n]+\]?\])\s*(?:#.*)?(?:\r?\n)?$', line)
            if m: out.append((pos, pos + len(line), m.group(1)))
        i = 0
        while i < len(line):
            if mode:
                if line.startswith(mode, i): mode = None; i += 3
                else: i += 1
            elif line.startswith(('"""', "'''"), i): mode = line[i:i + 3]; i += 3
            elif line[i] == '#': break
            else: i += 1
        pos += len(line)
    return out


def table_range(text, wanted):
    hs = headers(text)
    for n, (start, _, name) in enumerate(hs):
        if name == wanted:
            return start, hs[n + 1][0] if n + 1 < len(hs) else len(text)
    return None


def marker_span(text, begin, end):
    starts, finishes, mode, pos = [], [], None, 0
    for line in text.splitlines(True):
        if mode is None:
            if line.strip() == begin:
                starts.append(pos)
            elif line.strip() == end:
                finishes.append(pos + len(line))
        i = 0
        while i < len(line):
            if mode:
                if line.startswith(mode, i):
                    mode = None
                    i += 3
                else:
                    i += 1
            elif line.startswith(('"""', "'''"), i):
                mode = line[i:i + 3]
                i += 3
            elif line[i] == '#':
                break
            else:
                i += 1
        pos += len(line)
    if not starts and not finishes:
        return None
    if len(starts) != 1 or len(finishes) != 1 or starts[0] >= finishes[0]:
        raise ValueError(f'unbalanced {begin.removeprefix("# ").removesuffix(" >>>")} markers')
    return starts[0], finishes[0]


def dedupe_owned_sessionstart(text):
    table = table_range(text, '[hooks]')
    if not table:
        return text
    mode, pos = None, 0
    for line in text.splitlines(True):
        outside = mode is None
        i = 0
        while i < len(line):
            if mode:
                if line.startswith(mode, i):
                    mode = None
                    i += 3
                else:
                    i += 1
            elif line.startswith(('"""', "'''"), i):
                mode = line[i:i + 3]
                i += 3
            elif line[i] == '#':
                break
            else:
                i += 1
        if outside and table[0] <= pos < table[1] and re.match(r'\s*SessionStart\s*=', line):
            updated = re.sub(
                r',\s*\{\s*matcher\s*=\s*"startup\|resume\|clear\|compact".*?\]\s*\}',
                '', line, count=1,
            )
            return text[:pos] + updated + text[pos + len(line):]
        pos += len(line)
    return text


def main():
    op, path, *args = sys.argv[1:]
    text = open(path, encoding='utf-8').read()
    data = {} if op == 'hooks' else parse(path)
    nl = '\r\n' if '\r\n' in text else '\n'
    begin = '# >>> codebase-memory-mcp MCP >>>'
    finish = '# <<< codebase-memory-mcp MCP <<<'
    if op == 'mcp':
        section = data.get('mcp_servers', {}).get('codebase-memory-mcp')
        r = table_range(text, '[mcp_servers.codebase-memory-mcp]')
        allowed = {'command', 'args', 'env_vars', 'tools'}
        if (not isinstance(section, dict) or set(section) - allowed or not r or
                marker_span(text, begin, finish) is not None): return
        command = section.get('command', '')
        if not isinstance(command, str) or not re.search(r'codebase-memory-mcp(?:\.exe)?$', command): return
        start, end = r
        block = text[start:end].rstrip('\r\n')
        atomic(path, text[:start] + begin + nl + block + nl + finish + nl + text[end:])
    elif op == 'suspend':
        tables = data.get('mcp_servers', {}).get('codebase-memory-mcp', {})
        tools = tables.get('tools', {}) if isinstance(tables, dict) else {}
        ranges = [table_range(text, f'[mcp_servers.codebase-memory-mcp.tools.{k}]') for k in tools]
        ranges = [r for r in ranges if r]
        saved = '\n\n'.join(text[a:b].strip('\r\n') for a, b in ranges)
        for a, b in sorted(ranges, reverse=True): text = text[:a] + text[b:]
        if ranges: atomic(path, text)
        print(base64.b64encode(saved.encode()).decode())
    elif op == 'restore':
        if args and args[0]:
            saved = base64.b64decode(args[0]).decode()
            atomic(path, text.rstrip('\r\n') + nl + nl + saved.replace('\n', nl) + nl)
    elif op == 'hooks':
        b, e = '# >>> codebase-memory-mcp SessionStart >>>', '# <<< codebase-memory-mcp SessionStart <<<'
        span = marker_span(text, b, e)
        if span:
            candidate = text[:span[0]] + text[span[1]:]
            candidate_data = tomllib.loads(candidate)
            hooks = candidate_data.get('hooks', {})
            if isinstance(hooks, dict) and 'SessionStart' in hooks:
                atomic(path, candidate)
            return

        hooks = parse(path).get('hooks', {})
        if not isinstance(hooks, dict) or not isinstance(hooks.get('SessionStart'), list):
            return
        new = dedupe_owned_sessionstart(text)
        if new != text:
            atomic(path, new)


if __name__ == '__main__':
    try: main()
    except Exception as e:
        print(str(e), file=sys.stderr); sys.exit(1)
