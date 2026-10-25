# The stubs calibrate.sh stub writes over product files for the undefined-imports audit, shared with
# check-evidence.sh rule 10b, which compares the files an audit run records with them (bash 3.2
# compatible). A stub's exports are all undefined (None in Python).

# vetdd_stub_text <kind>: the stub of a kind on standard output; non-zero for an unknown kind.
#   esm      an ES module with no exports
#   cjs      an empty CommonJS module
#   guarded  an empty CommonJS module that is also valid as an ES module
#   py       a Python module whose every attribute is None (dunder names excepted)
vetdd_stub_text() {
  case "$1" in
    esm) printf 'export {};\n' ;;
    cjs) printf 'module.exports = {};\n' ;;
    guarded) printf 'if (typeof module !== "undefined") { module.exports = {}; }\n' ;;
    py) printf "def __getattr__(name):\n    if name.startswith('__') and name.endswith('__'):\n        raise AttributeError(name)\n    return None\n" ;;
    *) return 1 ;;
  esac
}

# vetdd_stub_kinds <path>: the kinds a file with this extension (ASCII letter case ignored) can be stubbed
# with, one per line, whatever its package.json says; nothing for an extension with no stub.
vetdd_stub_kinds() {
  case "$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')" in
    *.cjs|*.cts) echo cjs ;;
    *.mjs|*.mts) echo esm ;;
    *.js|*.ts|*.tsx|*.jsx) printf 'esm\nguarded\n' ;;
    *.py) echo py ;;
  esac
}
