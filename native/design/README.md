# PD Bridge native design system

The approved hybrid direction uses Calm Editorial for recording and review, with Modern Health Intelligence reserved for local Insights and the report action. The reference board is archived in `docs/screenshots/native-simulator/approved-hybrid-2026-11-26/` beside actual simulator captures.

`PDDesignSystem.swift` holds the app's adaptive color tokens, spacing and minimum target dimensions, scalable double-arch mark, native landscape paths, and reusable symptom card. `bridge-mark.svg` is the source vector for the matching raster icons. Run `python3 native/design/generate_brand_assets.py` from the repository root to regenerate icon and launch assets. The generator uses Pillow at asset-generation time and no network service.

| Token | Light value | Use |
| --- | --- | --- |
| Deep teal | `#124C47` | Patient actions and mark |
| Jade | `#26786D` | Secondary arch and illustration |
| Soft sage | `#DCECE4` | Cards and selected navigation |
| Warm ivory | `#F7F5EF` | Page background |
| Midnight navy | `#142E48` | Analytics and report text |
| Intelligence blue | `#245BC0` | Analytics selection and report review |
| Primary text | `#20332F` | Patient-facing text |

Calculated light-mode contrast ratios: primary text on ivory **12.22:1**; teal on sage **7.98:1**; white on teal **9.77:1**; navy on white **13.87:1**; white on blue **6.30:1**. Jade on sage is **4.30:1**, so that pairing is for decorative shapes rather than small text. Dark variants are defined in code, but visual dark-appearance validation remains open because the current simulator appearance override still produced a light app screenshot.

The design favors at least 64-point primary actions and 44-point minimum interaction targets. At accessibility Dynamic Type sizes the card grid and navigation reflow vertically. Reduce Motion removes decorative transitions. Charts show local event counts and are accompanied by text equivalents; missing diary entries are never presented as symptom-free days.
