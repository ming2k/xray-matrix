#!/bin/sh
# Authoritative workspace verification suite for xray-matrix.
# Enforces zero broken links, zero audience firewall violations,
# zero dangling ADR citations, and secret-free template hygiene.

set -eu

echo "==> 1. Checking documentation relative links & audience firewall..."
python3 scripts/check_doc_links.py

echo "==> 2. Checking ADR citation lineage..."
python3 scripts/check_adr_lineage.py

echo "==> 3. Running zero-leak pre-commit hook regression tests..."
sh .githooks/test-pre-commit.sh

echo ""
echo "=========================================================="
echo "  ALL ARCHITECTURAL & DOCUMENTATION CHECKS PASSED (100%)"
echo "=========================================================="
