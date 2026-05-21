// Standalone solc compile script for CI-less verification.
// Resolves @openzeppelin/contracts/... from node_modules and forge-std stays
// off the import graph because no source file imports it during compile.
//
// Usage: node scripts/compile.mjs <path-to-contracts-src> [output.json]
import solc from "solc";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const srcRoot = process.argv[2];
const outPath = process.argv[3] ?? "compile-out.json";
if (!srcRoot) {
    console.error("usage: node compile.mjs <src-dir> [out.json]");
    process.exit(2);
}

const sources = {};
function collect(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            collect(p);
        } else if (entry.name.endsWith(".sol")) {
            sources[path.relative(srcRoot, p)] = { content: fs.readFileSync(p, "utf8") };
        }
    }
}
collect(srcRoot);

function findImports(importPath) {
    // @openzeppelin/contracts/... → node_modules
    if (importPath.startsWith("@openzeppelin/")) {
        const resolved = path.join(process.cwd(), "node_modules", importPath);
        if (fs.existsSync(resolved)) {
            return { contents: fs.readFileSync(resolved, "utf8") };
        }
    }
    // relative imports inside contract project
    const candidates = [
        path.join(srcRoot, importPath),
        path.join(path.dirname(importPath), path.basename(importPath))
    ];
    for (const c of candidates) {
        if (fs.existsSync(c)) {
            return { contents: fs.readFileSync(c, "utf8") };
        }
    }
    return { error: "File not found: " + importPath };
}

const input = {
    language: "Solidity",
    sources,
    settings: {
        optimizer: { enabled: true, runs: 200 },
        evmVersion: "cancun",
        outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } }
    }
};

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));

let hasError = false;
if (output.errors) {
    for (const err of output.errors) {
        if (err.severity === "error") {
            hasError = true;
            console.error(err.formattedMessage);
        } else {
            console.warn(err.formattedMessage);
        }
    }
}
fs.writeFileSync(outPath, JSON.stringify(output, null, 2));

if (hasError) {
    console.error("\n❌ compile failed");
    process.exit(1);
}
const compiledContracts = Object.values(output.contracts ?? {}).flatMap((m) =>
    Object.entries(m).map(([k]) => k)
);
console.log("✓ compiled " + compiledContracts.length + " contracts");
for (const c of compiledContracts) console.log("  -", c);
