// Validate a JSON document against a JSON Schema, with no dependencies (the skill ships without node_modules).
// Supports the keyword subset vetdd's schemas use; any other keyword is an error, so a schema edit
// can never be silently ignored. tests/check-verdict.bats cross-checks it against ajv.
// Usage: node validate-json.mjs <schema.json> <data.json>
// Output: "valid" (exit 0), or one "<instance path> <message>" line per error (exit 1).
// Exit 2 on usage errors, an unreadable or unsupported schema.
import { readFileSync } from "node:fs";

const ANNOTATIONS = new Set(["$schema", "$id", "title", "description"]);

const typeOf = (v) =>
  v === null ? "null" : Array.isArray(v) ? "array" : Number.isInteger(v) ? "integer" : typeof v;
const isType = (v, t) =>
  t === "number" ? typeof v === "number" : t === "integer" ? Number.isInteger(v) : typeOf(v) === t;
const isObject = (v) => typeOf(v) === "object";
const show = (p) => p || "/";

const KEYWORDS = {
  type: (t, v, p, e) => isType(v, t) || e.push(`${show(p)} must be ${t}`),
  enum: (vals, v, p, e) => vals.includes(v) || e.push(`${show(p)} must be one of ${vals.join(", ")}`),
  pattern: (re, v, p, e) =>
    typeof v !== "string" || new RegExp(re, "u").test(v) || e.push(`${show(p)} must match ${re}`),
  minLength: (n, v, p, e) =>
    typeof v !== "string" || [...v].length >= n || e.push(`${show(p)} must have at least ${n} characters`),
  minimum: (n, v, p, e) => typeof v !== "number" || v >= n || e.push(`${show(p)} must be >= ${n}`),
  maximum: (n, v, p, e) => typeof v !== "number" || v <= n || e.push(`${show(p)} must be <= ${n}`),
  minItems: (n, v, p, e) => !Array.isArray(v) || v.length >= n || e.push(`${show(p)} must have at least ${n} items`),
  uniqueItems: (on, v, p, e) =>
    !on || !Array.isArray(v) || new Set(v.map((x) => JSON.stringify(x))).size === v.length ||
    e.push(`${show(p)} must not have duplicate items`),
  items: (s, v, p, e) => Array.isArray(v) && v.forEach((x, i) => check(s, x, `${p}/${i}`, e)),
  required: (keys, v, p, e) =>
    isObject(v) && keys.forEach((k) => k in v || e.push(`${show(p)} must have required property '${k}'`)),
  properties: (props, v, p, e) =>
    isObject(v) && Object.entries(props).forEach(([k, s]) => k in v && check(s, v[k], `${p}/${k}`, e)),
  additionalProperties: (s, v, p, e, schema) => {
    if (!isObject(v)) return;
    const known = new Set(Object.keys(schema.properties ?? {}));
    for (const k of Object.keys(v).filter((k) => !known.has(k))) {
      if (s === false) e.push(`${show(p)} must NOT have additional property ${JSON.stringify(k)}`);
      else if (isObject(s)) check(s, v[k], `${p}/${k}`, e);
    }
  },
};

function check(schema, data, path, errors) {
  for (const [kw, arg] of Object.entries(schema)) {
    if (ANNOTATIONS.has(kw)) continue;
    const rule = KEYWORDS[kw];
    if (!rule) throw new Error(`unsupported schema keyword '${kw}' at ${show(path)}`);
    rule(arg, data, path, errors, schema);
  }
}

const [schemaPath, dataPath] = process.argv.slice(2);
if (!schemaPath || !dataPath) {
  console.error("usage: validate-json.mjs <schema.json> <data.json>");
  process.exit(2);
}
let schema;
try {
  schema = JSON.parse(readFileSync(schemaPath, "utf8"));
} catch (err) {
  console.error(`cannot read schema ${schemaPath}: ${err.message}`);
  process.exit(2);
}
let data;
try {
  data = JSON.parse(readFileSync(dataPath, "utf8"));
} catch (err) {
  console.log(`/ is not valid JSON: ${err.message.replace(/\s+/g, " ")}`);
  process.exit(1);
}
const errors = [];
try {
  check(schema, data, "", errors);
} catch (err) {
  console.error(err.message);
  process.exit(2);
}
if (errors.length === 0) {
  console.log("valid");
} else {
  console.log(errors.join("\n"));
  process.exit(1);
}
