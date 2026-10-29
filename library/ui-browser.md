# ui-browser
Record what you saw in the browser, with the URL and action, using bin/ledger (phase=ui).

## When to Use
- Any change a user sees or clicks: components, pages, forms, styling.

## Steps
1. Reuse the project's existing components, tokens and patterns before inventing new ones.
2. Accessibility by default: semantic elements, labels, keyboard path, focus order, contrast, alt text.
3. Handle all states: loading, empty, error, success, and long or odd content.
4. Responsive: check a narrow and a wide viewport.
5. Run it for real in a browser: load the page, perform the user action, read the console for errors, watch the network for failures.
6. Add a UI-level test for the behavior (see library/tdd) where the repo has a harness.

## Red Flags
- "Looks right in code" without opening the page.
- Console errors ignored; div-with-onclick instead of a button.
- Styling hardcoded outside the design tokens.

## Verification
- Page loaded, action performed, no console errors, keyboard path works; observed result noted in the ledger.
