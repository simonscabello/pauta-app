# Pauta — app (Flutter)

> **O contexto do projeto não mora aqui.** Produto, regras de negócio,
> convenções, armadilhas e o fluxo de deploy estão no `AGENTS.md` do
> repositório **`simonscabello/pauta`**, que é a pasta *acima* desta:
>
> ```
> sistemas/        ← simonscabello/pauta     (AGENTS.md, docs/)
> ├─ pauta-app/    ← simonscabello/pauta-app (este repositório)
> └─ pauta-api/    ← simonscabello/pauta-api
> ```
>
> **Leia `../AGENTS.md` antes de escrever código.** Se ele não existir, este
> clone está fora do lugar: clone o `pauta` e rode o `setup.ps1` dele.
> Não copie seções para cá — duas cópias divergem, e já divergiram.

O mínimo para não quebrar nada sem ter lido o resto:

- O `flutter` não está no PATH: `$env:PATH = 'C:\Users\Acer\flutter\bin;' + $env:PATH`.
- Antes de entregar: `flutter analyze` ("No issues found!") e `flutter test`.
- Todo build de release precisa de
  `--dart-define=API_BASE_URL=https://backend-production-b304.up.railway.app`.
- `applicationId` e o pacote `louvor_app` **não mudam**: trocar publica outro app.
- Push em `master` publica a versão Web (Railway `pauta-frontend`); tag `vX.Y.Z`
  publica o APK (`.github/workflows/release-apk.yml`). O backend vai antes.
