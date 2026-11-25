# Histórico de ramas (fork JorchSF/codenotch)

Registro cronológico de las ramas propias aplicadas sobre el upstream
`vinzdg/codenotch`. Cada actualización del upstream se integra con rebase de
estas ramas sobre `upstream/main`.

| Fecha | Rama | PR / merge | Qué se hizo |
|---|---|---|---|
| 2026-11-01 | `fix/cursor-editor-token-rechazado` | Incluida en el PR de `fix/dock-al-arrancar` | Cursor: si la API rechaza el token del editor (401), se recurre a las credenciales de `cursor-agent`. Tests en `Tests/CursorUsageTests.swift`. |
| 2026-11-03 | `fix/dock-al-arrancar` | PR en JorchSF/codenotch (ver abajo) | La app arranca como agente (`LSUIElement: true` en `project.yml` / `Info.plist`) y fija la política de activación según la preferencia guardada, para que no parpadee el icono del Dock al elegir "solo barra de menús". |
| 2026-11-25 | `fix/dock-al-arrancar` | Merge en `main` del fork | Rebase de ambas ramas sobre upstream 1.26.0 (build 28), sin conflictos. `make test`: 2857 tests, 0 fallos, 9 omitidos. Instalada en /Applications con `make install`. Creación del fork y de este histórico. |
