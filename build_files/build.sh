#!/usr/bin/bash
# Monta a imagem Kairos Play OS em cima do Bazzite.
# Roda DENTRO do build do container (como root). Nada aqui depende de usuário:
# o que é do usuário (home, flatpaks, login automático) é feito no primeiro boot
# por /usr/libexec/kairos-play/primeiro-boot.sh.
set -euo pipefail

KIT_TAG="${KIT_TAG:-latest}"
REPO="Amorimelvis/kairos-play-atualizacoes"
DEST=/usr/share/kairos-play
KIT="$DEST/kit"

echo "== 1. Arquivos fixos do sistema (system_files) =="
cp -avf /ctx/system_files/. /
chmod 755 /usr/libexec/kairos-play/*.sh

echo "== 2. Kit Kairos Play ($KIT_TAG) =="
if [ "$KIT_TAG" = "latest" ]; then
  BASE_URL="https://github.com/$REPO/releases/latest/download"
else
  BASE_URL="https://github.com/$REPO/releases/download/$KIT_TAG"
fi
tmp="$(mktemp -d)"
curl -fsSL --retry 5 --retry-delay 5 -o "$tmp/kit-gamestick.zip"        "$BASE_URL/kit-gamestick.zip"
curl -fsSL --retry 5 --retry-delay 5 -o "$tmp/kit-gamestick.zip.sha256" "$BASE_URL/kit-gamestick.zip.sha256"
esperado="$(awk '{print $1; exit}' "$tmp/kit-gamestick.zip.sha256")"
obtido="$(sha256sum "$tmp/kit-gamestick.zip" | awk '{print $1}')"
if [ "$esperado" != "$obtido" ]; then
  echo "ERRO: sha256 do kit não confere ($obtido != $esperado)" >&2
  exit 1
fi
echo "kit sha256 ok: $obtido"
rm -rf "$KIT" && mkdir -p "$DEST"
( cd "$tmp" && python3 -m zipfile -e kit-gamestick.zip ex )
if [ -d "$tmp/ex/kit-gamestick" ]; then mv "$tmp/ex/kit-gamestick" "$KIT"; else mv "$tmp/ex" "$KIT"; fi
rm -rf "$tmp"
[ -f "$KIT/instalar-gamestick.sh" ] || { echo "ERRO: kit sem instalar-gamestick.sh" >&2; exit 1; }

echo "== 3. Trava de segurança: sem BIOS, sem segredos, sem lixo =="
# BIOS nunca entram na imagem (só o arquivo de instrução da pasta modelo).
find "$KIT" -type f \( -iname 'scph*' -o -iname '*bios*.bin' -o -iname '*bios*.rom' -o -iname '*bios*.zip' \
     -o -iname 'ps2-*.bin' -o -iname 'dc_boot.bin' -o -iname 'dc_flash.bin' -o -iname 'gba_bios.bin' \
     -o -iname 'neogeo.zip' -o -iname 'syscard*.pce' -o -iname 'sega_101.bin' -o -iname 'mpr-*.bin' \) -print -delete
find "$KIT" -path '*/bios/*' -type f ! -iname '*.txt' -print -delete
# Segredos / lixo de desenvolvimento
find "$KIT" \( -name '.env' -o -name '*.env' -o -name '*.pem' -o -name '*.key' -o -name 'id_rsa*' \
     -o -name '__pycache__' -o -name '*.pyc' -o -name '*.log' -o -name '*.iso' -o -name '*.zip' \) -print -exec rm -rf {} +
# ROMs: só os jogos gratuitos (homebrew) que o kit traz em roms/ e capas-homebrew/.
echo "ROMs no kit (homebrew, ver CREDITOS-HOMEBREW.md):"
find "$KIT/roms" -type f | sed 's/^/  /' || true
chown -R root:root "$KIT"
chmod -R u=rwX,go=rX "$KIT"
chmod 755 "$KIT/instalar-gamestick.sh"
tr -d '\n' < "$KIT/VERSAO" > "$DEST/VERSAO-KIT"
echo "versão do kit: $(cat "$DEST/VERSAO-KIT")"

echo "== 4. Abertura de boot (Plymouth, logo 3D neon + barra) =="
dnf5 install -y plymouth-plugin-script rpm-build
# Mesmo pacote que o kit instala por rpm-ostree, mas já dentro da imagem.
# Assim o instalar-splash-boot.sh do menu reconhece que já está instalado.
rb="$(mktemp -d)"
mkdir -p "$rb"/{SOURCES,SPECS,BUILD,RPMS,SRPMS,BUILDROOT}
tar -C "$KIT/splash-boot" -czf "$rb/SOURCES/kairos-play.tar.gz" kairos-play
cp "$KIT/splash-boot/kairos-play-plymouth.spec" "$rb/SPECS/"
rpmbuild --define "_topdir $rb" -bb "$rb/SPECS/kairos-play-plymouth.spec"
dnf5 install -y "$rb"/RPMS/noarch/kairos-play-plymouth-*.rpm
dnf5 remove -y rpm-build || true
rm -rf "$rb"
plymouth-set-default-theme kairos-play
grep -q 'Theme=kairos-play' /etc/plymouth/plymouthd.conf
# Initramfs novo com o tema (padrão Universal Blue)
KVER="$(ls /usr/lib/modules | sort -V | tail -n1)"
echo "kernel: $KVER"
export DRACUT_NO_XATTR=1
dracut --no-hostonly --kver "$KVER" --reproducible --add ostree --add plymouth -f "/usr/lib/modules/$KVER/initramfs.img"
chmod 0600 "/usr/lib/modules/$KVER/initramfs.img"
# Garante "splash" na linha do kernel (sem duplicar o que o Bazzite já põe)
if ! cat /usr/lib/bootc/kargs.d/*.toml 2>/dev/null | grep -q '"splash"'; then
  mkdir -p /usr/lib/bootc/kargs.d
  printf 'kargs = ["rhgb", "quiet", "splash"]\n' > /usr/lib/bootc/kargs.d/50-kairos-play.toml
fi
echo "kargs.d:"; cat /usr/lib/bootc/kargs.d/*.toml 2>/dev/null || true

echo "== 5. Bluetooth (controle PS4/Xbox reconecta sozinho) =="
ini_set() {
  python3 - "$@" <<'PY'
import sys, re
arq, sec, chave, valor = sys.argv[1:5]
try: linhas = open(arq).read().split("\n")
except FileNotFoundError: linhas = []
cab = "[%s]" % sec
i = next((n for n, l in enumerate(linhas) if l.strip() == cab), None)
if i is None:
    linhas += ["", cab, "%s=%s" % (chave, valor)]
else:
    fim = next((n for n in range(i+1, len(linhas)) if linhas[n].strip().startswith("[")), len(linhas))
    pad = re.compile(r"^\s*#?\s*%s\s*=" % re.escape(chave))
    for n in range(i+1, fim):
        if pad.match(linhas[n]): linhas[n] = "%s=%s" % (chave, valor); break
    else: linhas.insert(i+1, "%s=%s" % (chave, valor))
open(arq, "w").write("\n".join(linhas))
PY
}
mkdir -p /etc/bluetooth
ini_set /etc/bluetooth/main.conf Policy AutoEnable true
ini_set /etc/bluetooth/main.conf General FastConnectable true
ini_set /etc/bluetooth/input.conf General UserspaceHID true
ini_set /etc/bluetooth/input.conf General ClassicBondedOnly false
systemctl enable bluetooth.service

echo "== 6. Serviço de primeiro boot =="
systemctl enable kairos-play-primeiro-boot.service
systemctl enable kairos-play-primeiro-boot.path

echo "== 7. Identidade =="
sed -i 's/^VARIANT=.*/VARIANT="Kairos Play"/' /usr/lib/os-release || true
grep -q '^VARIANT=' /usr/lib/os-release || echo 'VARIANT="Kairos Play"' >> /usr/lib/os-release
echo "Kairos Play OS (kit $(cat "$DEST/VERSAO-KIT"))" > "$DEST/IMAGEM"

echo "== pronto =="
