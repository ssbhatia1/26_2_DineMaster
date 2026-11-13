#!/usr/bin/env bash
# ==============================================================================
# DineMaster — Isolated Environment Setup & Provisioning Script (Bash)
# ==============================================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
JDK_DIR="$VENV_DIR/jdk"
FLUTTER_DIR="$VENV_DIR/flutter"

echo "=================================================================="
echo "    DineMaster - Isolated Environment Provisioning (Bash)         "
echo "=================================================================="

mkdir -p "$VENV_DIR/Scripts"

echo "[1/4] Checking Isolated JDK..."
if [ -d "$JDK_DIR/bin" ]; then
    echo "  -> JDK present at: $JDK_DIR"
else
    echo "  -> Note: Place OpenJDK 21 in $JDK_DIR or set up symlink."
fi

echo "[2/4] Checking Isolated Flutter SDK..."
if [ -d "$FLUTTER_DIR/bin" ]; then
    echo "  -> Flutter present at: $FLUTTER_DIR"
else
    if command -v flutter >/dev/null 2>&1; then
        FLUTTER_SYSTEM="$(dirname "$(dirname "$(which flutter)")")"
        echo "  -> Linking Flutter from system: $FLUTTER_SYSTEM"
        ln -s "$FLUTTER_SYSTEM" "$FLUTTER_DIR"
    fi
fi

echo "[3/4] Resolving Frontend Dependencies..."
if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
    cd "$PROJECT_ROOT/frontend"
    "$FLUTTER_DIR/bin/flutter" pub get
    cd "$PROJECT_ROOT"
fi

echo "[4/4] Verifying Backend Maven Dependencies..."
if [ -x "$PROJECT_ROOT/backend/mvnw" ]; then
    cd "$PROJECT_ROOT/backend"
    export JAVA_HOME="$JDK_DIR"
    ./mvnw test-compile
    cd "$PROJECT_ROOT"
fi

echo "=================================================================="
echo "  Environment Ready! Run 'source ./activate.sh' to activate.      "
echo "=================================================================="
