# Unexpected remote build loaders — 28 October 2026

During the Phase 4 pre-PR fetch, origin/dev moved by a forced update from 70a1bf6 to 2012881. Its tree added unexpected files and changed the POS scripts and website PostCSS configuration.

Static inspection (decoding strings as data, never evaluating them) identified encoded remote-code loaders in:
- init
- website/postcss.config.mjs
- public/fonts/fa-solid-700.otf (JavaScript disguised as a font)

The decoded text includes remote payload retrieval, eval and detached Node process creation. package.json added node init to dev/build. These remote files were not checked out or executed during this task. The completed builds used the prior clean configuration.

The cleanup commit restores the complete pre-rewrite tree, removing the newly introduced editor recommendations/font artifacts and reverting both build entry points. The return-request commit follows separately. This intentionally avoids preserving other artifacts introduced alongside the loaders; maintainers can restore any verified legitimate assets later.

Do not run the affected dev tree. Review repository access and the force-push source before merging. If these loaders were executed elsewhere, treat that environment and its available credentials as potentially exposed; the second-stage payload was not downloaded or assessed here. No claim is made that other machines or deployments are clean.

This PR does not rewrite remote history or deploy either application.
