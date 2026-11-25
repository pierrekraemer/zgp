# VolumeMesh (Planned)

> **Status: Not yet implemented.** Both [`src/models/volume/VolumeMesh.zig`](../../src/models/volume/VolumeMesh.zig) and [`src/models/VolumeMeshStore.zig`](../../src/models/VolumeMeshStore.zig) currently exist as empty placeholder files.

---

## Expected Architecture & Integration Path

When implemented, `VolumeMesh` is expected to follow the same layered conventions as [`SurfaceMesh`](surface-mesh.md):

1. **Model (`src/models/volume/VolumeMesh.zig`)**:
   - 3-dimensional combinatorial map (3-map adding the $\phi_3$ involution across shared faces between adjacent volumes) backed by `DataContainer`s (`dart_data`, `vertex_data`, `edge_data`, `face_data`, `volume_data`).
2. **Store (`src/models/VolumeMeshStore.zig`)**:
   - Central owner and observer hub matching [`SurfaceMeshStore.zig`](../../src/models/SurfaceMeshStore.zig): `VolumeMeshStdDatas` / `VolumeMeshStdData`, `VolumeMeshInfo`, `data_vbo`, `data_last_update`, primitive IBOs, and `leftPanel`.
3. **AppContext, Modules & UI**:
   - Add `.volume_mesh: *VolumeMesh` to `AppContext.ModelSelection` and `.volume_mesh: bool = false` to `Module.SupportedModels`.
   - Add `VolumeMeshStore` event hooks to `Module.VTable`.
   - Implement `VolumeMeshStdDatas.zig`, `VolumeMeshRenderer.zig`, and `imgui.zig` selection widgets, then wire everything into `AppContext.zig`.
4. **Algorithm Docs**:
   - Future volume mesh algorithms will be documented one-per-file under `docs/05-models/volume-mesh/`.

See [`docs/recipes.md`](../recipes.md#5-add-a-new-model-type-eg-volumemesh) for the complete integration checklist.
