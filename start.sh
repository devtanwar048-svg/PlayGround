#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_WEB_DIR="${OPENCODE_WEB_DIR:-/home/runner/work/_temp/omgithub-web}"
RUNTIME_DIR="${RUNTIME_DIR:?RUNTIME_DIR must point to the OMGithub runtime}"
PORT="${PORT:-3000}"
export PROJECT_DIR OPENCODE_WEB_DIR PORT

cd "$PROJECT_DIR"
/usr/bin/time -p mkdir -p "$PROJECT_DIR/dist" "$OPENCODE_WEB_DIR"
# This project is dependency-free static HTML; copying the entrypoint is its build.
/usr/bin/time -p cp "$PROJECT_DIR/index.html" "$PROJECT_DIR/dist/index.html"
/usr/bin/time -p test -s "$PROJECT_DIR/dist/index.html"
/usr/bin/time -p node -e 'const fs=require("node:fs"); const path=require("node:path"); const project=path.resolve(process.env.PROJECT_DIR); const directory=path.join(project,"dist"); fs.writeFileSync(path.join(process.env.OPENCODE_WEB_DIR,"deployment-output.json"),JSON.stringify({project,directory}));'
exec /usr/bin/time -p node "$RUNTIME_DIR/scripts/default-start.mjs"
