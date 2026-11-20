# Kairos Play OS

Instalador (ISO) do Kairos Play: um Bazzite que liga direto na tela de jogos Kairos,
sem senha, com a abertura neon 3D, o tema e os ícones Kairos, controle, Bluetooth,
atualização pelo menu e importação de jogos e capas do pendrive.

## Como é montado

- `Containerfile` + `build_files/build.sh`: imagem bootc em cima de `ghcr.io/ublue-os/bazzite:stable`
  (KDE, Intel/AMD). No build ela baixa o **último release** do kit de
  `Amorimelvis/kairos-play-atualizacoes` (confere o sha256), instala a abertura de boot
  (Plymouth) e refaz o initramfs.
- `system_files/`: serviço de primeiro boot, tampa fechada, uinput do controle e lista de apps.
- No primeiro boot (`/usr/libexec/kairos-play/primeiro-boot.sh`), para o usuário criado na instalação:
  apps do Flathub (se faltarem), script root + sudoers **estreito** (só ele, sem `NOPASSWD: ALL`),
  login automático em `/etc/plasmalogin.conf`, sessão Kairos Play e o próprio
  `instalar-gamestick.sh --atualizar` do kit. Log: `/var/lib/kairos-play/primeiro-boot.log`.
- `disk_config/iso.toml`: instalador Anaconda (bootc-image-builder, tipo `anaconda-iso`).
- `.github/workflows/build.yml`: publica `ghcr.io/amorimelvis/kairos-play-iso:latest` (todo dia e a cada push).
- `.github/workflows/build-iso.yml`: gera a ISO e guarda como artefato do Actions.

## O que NÃO vai na imagem

ROMs comerciais, BIOS, senhas, `.env`. Só os jogos gratuitos (homebrew) do kit.
Jogos e BIOS continuam vindo do pendrive do dono do aparelho.

## Gravar e instalar

1. Baixe `kairos-play-os-AAAAMMDD.iso` (artefato do workflow "ISO Kairos Play OS").
2. Grave num pendrive de 16 GB ou mais com o **Fedora Media Writer** ("Selecionar arquivo .iso")
   ou o **Rufus** (modo **DD** quando ele perguntar). Isso apaga o pendrive.
3. No notebook: ligue segurando a tecla do menu de boot (Samsung: **F10** ou **Esc**) e escolha o pendrive.
4. No instalador: idioma, disco (apaga o disco!), Wi-Fi e **crie o usuário**. Instalar.
5. Reinicie. Se aparecer a tela azul **MOK**: Enroll MOK > Continue > Yes > senha `universalblue` > Reboot.
6. O primeiro boot demora um pouco mais (prepara o Kairos Play). Depois liga direto no Kairos Play.
7. Na primeira abertura o RetroDECK pergunta onde guardar: escolha **Home Directory**.
