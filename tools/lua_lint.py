"""Lua 5.1 parser and scope checker (no Lua interpreter needed).

Parses every file completely (recursive descent after the Lua 5.1 grammar)
and reports
  * syntax errors,
  * reads of global names that are neither Lua/BO3 globals nor known from the
    decompiled stock UI (typos, locals used before their declaration),
  * assignments to new global names (BO3 calls DisableGlobals() after the
    frontend is loaded, so creating globals later fails at runtime).

Known BO3 globals are collected from the decompiled stock Lua when the folder
exists (--stock, default %TEMP%/bo3-decompiled), plus the list below.

Usage: python tools/lua_lint.py [--stock DIR] <file-or-directory> [...]
"""
import os
import re
import sys
from pathlib import Path

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

LUA_GLOBALS = {
    "assert", "collectgarbage", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "print",
    "rawequal", "rawget", "rawset", "require", "select", "setmetatable", "tonumber", "tostring", "type",
    "unpack", "xpcall", "string", "table", "math", "os", "coroutine", "debug", "_G", "_VERSION",
}
# Engine-provided globals that are not assigned anywhere in Lua source.
ENGINE_GLOBALS = {"Engine", "Enum", "LuaEnums", "RegisterImage", "RegisterMaterial", "DebugPrint", "ConstructLUIElement", "ProjectRootCoordinate"}


class LuaSyntaxError(Exception):
    pass


TOKEN_RE = re.compile(
    r"(?P<ws>[ \t\r\f\v]+)"
    r"|(?P<nl>\n)"
    r"|(?P<longcomment>--\[(?P<lceq>=*)\[.*?\](?P=lceq)\])"
    r"|(?P<comment>--[^\n]*)"
    r"|(?P<longstring>\[(?P<lseq>=*)\[.*?\](?P=lseq)\])"
    r"|(?P<string>\"(?:\\.|\\\n|[^\"\\\n])*\"|'(?:\\.|\\\n|[^'\\\n])*')"
    r"|(?P<number>0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)"
    r"|(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"|(?P<op>\.\.\.|\.\.|==|~=|<=|>=|[-+*/%^#<>=(){}\[\];:,.])",
    re.S,
)


def tokenize(text, path):
    tokens = []
    pos, line = 0, 1
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise LuaSyntaxError(f"{path}:{line}: unexpected character {text[pos]!r}")
        kind = m.lastgroup
        value = m.group(0)
        if kind in ("lceq", "lseq"):
            kind = "longcomment" if value.startswith("--") else "longstring"
        if kind == "name" and value in KEYWORDS:
            kind = "kw"
        elif kind == "longstring":
            kind = "string"
        if kind not in ("ws", "nl", "comment", "longcomment"):
            tokens.append((kind, value, line))
        line += value.count("\n")
        pos = m.end()
    tokens.append(("eof", "<eof>", line))
    return tokens


BINOPS = {"+", "-", "*", "/", "%", "^", "..", "==", "~=", "<", "<=", ">", ">=", "and", "or"}
UNOPS = {"-", "not", "#"}


class Parser:
    def __init__(self, tokens, path, known):
        self.t = tokens
        self.i = 0
        self.path = path
        self.known = known
        self.scopes = [set()]
        self.problems = []

    # token helpers -------------------------------------------------------
    def peek(self, offset=0):
        return self.t[min(self.i + offset, len(self.t) - 1)]

    def check(self, value):
        kind, v, _ = self.peek()
        return v == value and kind in ("kw", "op")

    def accept(self, value):
        if self.check(value):
            self.i += 1
            return True
        return False

    def expect(self, value, context=""):
        if not self.accept(value):
            kind, v, line = self.peek()
            raise LuaSyntaxError(f"{self.path}:{line}: '{value}' expected{context} near '{v}'")

    def name(self):
        kind, v, line = self.peek()
        if kind != "name":
            raise LuaSyntaxError(f"{self.path}:{line}: name expected near '{v}'")
        self.i += 1
        return v, line

    # scopes ----------------------------------------------------------------
    def declare(self, name):
        self.scopes[-1].add(name)

    def is_local(self, name):
        return any(name in scope for scope in self.scopes)

    def use_global(self, name, line, write=False):
        if self.is_local(name) or name in self.known:
            return
        what = "new global assigned" if write else "unknown global"
        self.problems.append(f"{self.path}:{line}: {what} '{name}'")

    # grammar ---------------------------------------------------------------
    def chunk(self):
        self.block()
        if self.peek()[0] != "eof":
            kind, v, line = self.peek()
            raise LuaSyntaxError(f"{self.path}:{line}: '<eof>' expected near '{v}'")

    def block_follow(self):
        kind, v, _ = self.peek()
        return kind == "eof" or (kind == "kw" and v in ("else", "elseif", "end", "until"))

    def block(self):
        self.scopes.append(set())
        self.block_body()
        self.scopes.pop()

    def block_body(self):
        while not self.block_follow():
            if self.check("return"):
                self.i += 1
                if not self.block_follow() and not self.check(";"):
                    self.exprlist()
                self.accept(";")
                break
            if self.check("break"):
                self.i += 1
                self.accept(";")
                continue
            self.statement()
            self.accept(";")

    def scoped_block(self, names=()):
        self.scopes.append(set(names))
        self.block()
        self.scopes.pop()

    def statement(self):
        kind, v, line = self.peek()
        if kind == "kw":
            if v == "if":
                self.i += 1
                self.expr()
                self.expect("then")
                self.block()
                while self.accept("elseif"):
                    self.expr()
                    self.expect("then")
                    self.block()
                if self.accept("else"):
                    self.block()
                self.expect("end", " (to close 'if' at line %d)" % line)
                return
            if v == "while":
                self.i += 1
                self.expr()
                self.expect("do")
                self.block()
                self.expect("end", " (to close 'while' at line %d)" % line)
                return
            if v == "do":
                self.i += 1
                self.block()
                self.expect("end", " (to close 'do' at line %d)" % line)
                return
            if v == "for":
                self.i += 1
                first, _ = self.name()
                if self.accept("="):
                    self.expr()
                    self.expect(",")
                    self.expr()
                    if self.accept(","):
                        self.expr()
                    self.expect("do")
                    self.scoped_block([first])
                else:
                    names = [first]
                    while self.accept(","):
                        names.append(self.name()[0])
                    self.expect("in")
                    self.exprlist()
                    self.expect("do")
                    self.scoped_block(names)
                self.expect("end", " (to close 'for' at line %d)" % line)
                return
            if v == "repeat":
                self.i += 1
                # 'until' sees the locals of the loop body.
                self.scopes.append(set())
                self.block_body()
                self.expect("until")
                self.expr()
                self.scopes.pop()
                return
            if v == "function":
                self.i += 1
                base, name_line = self.name()
                self.use_global(base, name_line, write=not self.check(".") and not self.check(":"))
                is_method = False
                while self.check(".") or self.check(":"):
                    is_method = self.check(":")
                    self.i += 1
                    self.name()
                    if is_method:
                        break
                self.funcbody(["self"] if is_method else [])
                return
            if v == "local":
                self.i += 1
                if self.accept("function"):
                    fname, _ = self.name()
                    self.declare(fname)
                    self.funcbody([])
                    return
                names = [self.name()[0]]
                while self.accept(","):
                    names.append(self.name()[0])
                if self.accept("="):
                    self.exprlist()
                for n in names:
                    self.declare(n)
                return
        # expression statement: call or assignment
        targets = [self.suffixedexp(assign=True)]
        if self.check("=") or self.check(","):
            while self.accept(","):
                targets.append(self.suffixedexp(assign=True))
            self.expect("=")
            self.exprlist()
            for target in targets:
                if target[0] == "name":
                    self.use_global(target[1], target[2], write=True)
                elif target[0] == "call":
                    raise LuaSyntaxError(f"{self.path}:{line}: cannot assign to a function call")
        else:
            if targets[0][0] != "call":
                raise LuaSyntaxError(f"{self.path}:{line}: syntax error (statement is not a call or assignment)")

    def funcbody(self, params):
        _, _, line = self.peek()
        self.expect("(")
        names = list(params)
        if not self.check(")"):
            while True:
                if self.accept("..."):
                    names.append("arg")
                    break
                names.append(self.name()[0])
                if not self.accept(","):
                    break
        self.expect(")")
        self.scopes.append(set(names))
        self.block()
        self.scopes.pop()
        self.expect("end", " (to close 'function' at line %d)" % line)

    def exprlist(self):
        self.expr()
        while self.accept(","):
            self.expr()

    def primaryexp(self, assign):
        kind, v, line = self.peek()
        if kind == "name":
            self.i += 1
            if assign:
                return ("name", v, line)
            self.use_global(v, line)
            return ("name", v, line)
        if self.accept("("):
            self.expr()
            self.expect(")")
            return ("paren", None, line)
        raise LuaSyntaxError(f"{self.path}:{line}: unexpected symbol near '{v}'")

    def suffixedexp(self, assign=False):
        base = self.primaryexp(assign)
        result = base
        first = True
        while True:
            kind, v, line = self.peek()
            if assign and first and base[0] == "name" and not (self.check("=") or self.check(",")):
                # the base name is read (a.b = 1 reads a; f() reads f)
                self.use_global(base[1], base[2])
            first = False
            if self.accept("."):
                self.name()
                result = ("field", None, line)
            elif self.accept("["):
                self.expr()
                self.expect("]")
                result = ("index", None, line)
            elif self.accept(":"):
                self.name()
                self.callargs()
                result = ("call", None, line)
            elif self.check("(") or kind == "string" or self.check("{"):
                self.callargs()
                result = ("call", None, line)
            else:
                return result

    def callargs(self):
        kind, v, line = self.peek()
        if kind == "string":
            self.i += 1
        elif self.check("{"):
            self.table()
        else:
            self.expect("(")
            if not self.check(")"):
                self.exprlist()
            self.expect(")")

    def table(self):
        self.expect("{")
        while not self.check("}"):
            if self.accept("["):
                self.expr()
                self.expect("]")
                self.expect("=")
                self.expr()
            elif self.peek()[0] == "name" and self.peek(1)[1] == "=" and self.peek(1)[0] == "op":
                self.i += 2
                self.expr()
            else:
                self.expr()
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}")

    def simpleexp(self):
        kind, v, line = self.peek()
        if kind in ("number", "string"):
            self.i += 1
        elif kind == "kw" and v in ("nil", "true", "false"):
            self.i += 1
        elif self.accept("..."):
            pass
        elif self.check("{"):
            self.table()
        elif self.accept("function"):
            self.funcbody([])
        else:
            self.suffixedexp()

    def expr(self):
        kind, v, _ = self.peek()
        if v in UNOPS and kind in ("op", "kw"):
            self.i += 1
            self.expr_unary()
        else:
            self.simpleexp()
        while True:
            kind, v, _ = self.peek()
            if v in BINOPS and kind in ("op", "kw"):
                self.i += 1
                self.expr_unary()
            else:
                return

    def expr_unary(self):
        kind, v, _ = self.peek()
        if v in UNOPS and kind in ("op", "kw"):
            self.i += 1
            self.expr_unary()
        else:
            self.simpleexp()


def stock_globals(folder):
    names = set()
    if not folder or not Path(folder).is_dir():
        return names
    # Also indented: stock files guard definitions with "if not X then X = {} end".
    assign = re.compile(r"^[ 	]*([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]", re.M)
    function = re.compile(r"^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*[\(\.:]", re.M)
    for path in Path(folder).rglob("*.lua"):
        text = path.read_text(encoding="utf-8", errors="replace")
        names.update(assign.findall(text))
        names.update(function.findall(text))
    return names


def lint(path, known):
    text = path.read_text(encoding="utf-8", errors="replace")
    try:
        parser = Parser(tokenize(text, path), path, known)
        parser.chunk()
        return parser.problems
    except LuaSyntaxError as error:
        return [f"SYNTAX {error}"]


def main(args):
    stock = os.path.join(os.environ.get("TEMP", ""), "bo3-decompiled")
    if args[:1] == ["--stock"]:
        stock, args = args[1], args[2:]
    known = LUA_GLOBALS | ENGINE_GLOBALS | stock_globals(stock)
    if len(known) < 100:
        print(f"Hinweis: keine dekompilierten Stock-Dateien unter {stock} - nur Syntax wird geprüft")
    files = []
    for arg in args:
        p = Path(arg)
        files.extend(sorted(p.rglob("*.lua")) if p.is_dir() else [p])
    problems = []
    for f in files:
        found = lint(f, known)
        if len(known) < 100:
            found = [line for line in found if line.startswith("SYNTAX")]
        problems.extend(found)
    for line in problems:
        print(line)
    print(f"{len(files)} Datei(en) geparst, {len(problems)} Problem(e)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
