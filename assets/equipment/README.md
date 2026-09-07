# Equipment illustrations

`technical-equipment.png` is bundled category artwork generated with the built-in
ImageGen tool on 2026-09-07. It is not a photograph or an exact-model claim.

The approved reference was the thin teal generator illustration in the original
Field Notes concept board. The final set includes the thirteen seeded asset
types (including two different dredges and generic equipment), pump, crane, and
engine. Selection uses complete seed IDs or exact normalized catalog type names;
an unknown type resolves to generic equipment.

NOW-018 adds sixteen individually generated drawings for RIB/inflatable boat,
aluminum skiff, cabin cruiser, commercial trawler, purse seiner, tugboat,
backhoe loader, skid steer, dump truck, motor grader, forklift, telehandler,
road roller, mobile crane, tower crane and davit. Each has its own same-named
PNG file (kebab-case). These cover all 32 standard types in
`seed/asset-types.json`, with Pump, Marine Crane and Diesel Engine using the
existing dedicated atlas drawings. Marine Crane, Mobile Crane, Tower Crane and
Davit are separate categories.

The generator returned neutral paper instead of genuine alpha. The widget
extracts teal ink with alpha = clamp(6 * (blue - red) - 12, 0, 255), then tints the
linework for the active theme. Neutral paper becomes transparent; fine edges
retain partial opacity. The small offset suppresses near-neutral paper grain.
This is entirely local rendering with no image service.

The individual drawings are also 1254 square, with complete subjects and clear
margins; they use the whole image rather than an atlas crop. Their finer source
strokes use alpha = clamp(14 * (blue - red) - 28, 0, 255) after downsampling.
This keeps the same neutral-paper rejection threshold while strengthening
thumbnail linework. The original atlas treatment remains unchanged.

The generator also did not obey exact equal-cell placement. Inspected subject
rectangles in `equipment_art_catalog.dart` retain each complete drawing. Do not
replace this file with another atlas without updating and testing those bounds.

## Prompt record

Initial prompt: create a 4 by 4 sheet matching the reference's delicate thin teal
engineering linework, mostly transparent interiors, minimal hatch shading, no
brands or labels. Row order: motor yacht, sailing yacht, catamaran, sport fisher;
panga/work boat, center console, hydraulic dredge, cutter suction dredge;
excavator, wheel loader, bulldozer, diesel generator; pump, marine crane,
generic cabinet and toolbox, marine engine. Request genuine transparency and
complete centered equipment within each cell.

Final edit prompt: remove the checkerboard, use pure white with no patterns,
gradients or shadows; retain all sixteen fine teal drawings in the same order
and style, requesting ample invisible equal-cell margins. The final file is
1254 by 1254 pixels. Crop and chroma tests verify the actual result.

NOW-018 prompts each describe one machine or vessel, its identifying hull,
chassis, lifting gear or attachment, and ask for a complete centered three-quarter
technical drawing with delicate dark-teal pen lines, accurate proportions, white
open interiors, sparse hatching and a white background. Prompts exclude labels,
brands, people, scenery, gradients and filled shadows. All sixteen drawings were
generated with the built-in ImageGen tool on 2026-09-07 and inspected individually.
Native light/dark contact sheets verify the rendering used by the app.
