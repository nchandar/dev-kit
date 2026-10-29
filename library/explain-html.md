# explain-html
Record the page path with bin/ledger (phase=explain).

## When to Use
- The user asks how something works, wants an architecture or data-flow explanation, or a research report is about a system.

## Steps
1. Read the real code or docs first. List components, what data each passes on, and the order. No invented boxes.
2. One self-contained file, `<task>/report.html` unless a path is given: inline SVG, CSS, JS. No network, no build. Light and dark via `prefers-color-scheme`; readable at phone width.
3. Layout, top to bottom: one-sentence summary; the animated diagram with a step panel; a components table (name, job, owns); a decisions table (choice, why, alternative rejected); open questions.
4. Diagram: nodes are components, arrows carry data and are labelled with the payload. A dot travels each arrow in order. Controls: play, pause, step, replay.
5. Every step shows one line of what moves and one line of why. Clicking or focusing a node shows what it does, why it exists, and what breaks without it. Cite the file:line it maps to.
6. Keep it small: at most 8 nodes per view (split into views past that), one-line whys, tables instead of paragraphs.
7. Under `prefers-reduced-motion`, show the steps as a static numbered list.
8. Open it: `open <file>` on macOS, `xdg-open <file>` on Linux. Tell the user the path.

## Red Flags
- Boxes that are not in the code; arrows with no payload label; animation with no step text.
- External scripts or fonts; walls of text; unreadable colors in dark mode.

## Verification
- The page works offline; every node and arrow maps to a real file or call; steps play in order; both tables are present; the ledger has the path.
