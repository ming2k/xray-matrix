# Documentation Style & Hyperlink Standards

This document specifies the style guide, markdown conventions, and hyperlink standards for all documentation in `xray-matrix`.

---

## 1. Hyperlink Standards

1. **Explicit Relative Paths**: All cross-references between documentation files must use explicit relative paths (e.g., `[Architecture](../../explanation/architecture.md)`).
2. **Never Use Absolute File URLs**: Never write hardcoded local paths (e.g., `/home/...` or `file://...`) or absolute repository URLs that break across mirrors or offline clones.
3. **Target Existence Guarantee**: Every relative link must resolve to a valid file. Dead links or broken anchors are treated as build failures.
4. **Anchor Hygiene**: When linking to section headers, use clean GitHub-flavored kebab-case anchors matching the heading text.

---

## 2. Formatting & Markdown Conventions

1. **Header Hierarchy**:
   - Exactly one `# Level 1 Heading` per file at line 1.
   - Subsections must descend logically: `## Level 2`, followed by `### Level 3`. Never skip heading levels (e.g., `#` directly to `###`).
2. **Fenced Code Blocks**:
   - Always declare an explicit language identifier on fenced code blocks (e.g., ````sh````, ````json````, ````nft````, ````ini````, ````text````). Never leave fences untyped.
3. **Example Values and Placeholders**:
   - Every example secret in public documentation and templates must be unmistakably fake (e.g., `REDACTED`, `00000000-0000-0000-0000-000000000000`, `203.0.113.x`, `example.com`).
   - Never embed real private keys or live server IPs.
4. **Tables and Lists**:
   - Use clean Markdown tables with aligned delimiter pipes.
   - For lists, prefer `-` for unordered bullet points and `1.` for sequential step-by-step procedures.

---

## 3. Tone and Technical Precision

1. **Objective and Actionable**: Write in direct, technical, active voice. Focus on commands, network mechanisms, packet transformations, and failure modes.
2. **Mechanisms Over Aspirations**: When documenting constraints, cite the specific kernel table, iptables/nftables hook, or systemd setting enforcing it.
3. **Zero Dead Links & Stale References**: Regularly verify link resolution across the repository tree.
