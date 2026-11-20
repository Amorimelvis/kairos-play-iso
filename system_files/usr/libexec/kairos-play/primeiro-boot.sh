#!/usr/bin/bash
# Kairos Play OS - primeiro boot.
# Roda como root (systemd), antes da tela de login. Prepara o PRIMEIRO usuário
# criado na instalação para ligar direto no Kairos Play:
#   1. apps do Flathub (RetroDECK, Chrome, YouTube TV, mpv, Kodi), se ainda faltarem
#   2. script root do Kairos Play + sudoers ESTREITO (só esse script, sem NOPASSWD: ALL)
#   3. kit do usuário, sessão Kairos Play, login automático (/etc/plasmalogin.conf),
#      tema/ícones do ES-DE, controle, atualizador do menu, vigia do pendrive
# Idempotente: pode rodar de novo. Só marca "ok" quando tudo que importa ficou pronto.
set -u
KIT=/usr/share/kairos-play/kit
ESTADO=/var/lib/kairos-play
LOG="$ESTADO/primeiro-boot.log"
HELPER=/usr/local/libexec/kairos-play-atualizar-root
SUDOERS=/etc/sudoers.d/91-kairos-play-atualizar
SESSAO=kairos-play.desktop

mkdir -p "$ESTADO"
chmod 755 "$ESTADO"
exec >>"$LOG" 2>&1
echo
echo "== Kairos Play primeiro boot: $(date '+%F %T') args=$* =="

aviso_tela() {
  echo ">> $*"
  if command -v plymouth >/dev/null 2>&1 && plymouth --ping 2>/dev/null; then
    plymouth display-message --text="$*" 2>/dev/null || true
  fi
}

# --- usuário: o primeiro "humano" (UID 1000+) criado na instalação ----------
usuario="$(awk -F: '$3>=1000 && $3<60000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)"
if [ -z "$usuario" ]; then
  echo "ainda não existe usuário; tento de novo quando ele for criado"
  exit 0
fi
home="$(getent passwd "$usuario" | cut -d: -f6)"
if [ -z "$home" ] || [ ! -d "$home" ]; then
  echo "home de $usuario ainda não existe; tento de novo depois"
  exit 0
fi
echo "usuário: $usuario  home: $home"
como_usuario() {
  runuser -u "$usuario" -- env HOME="$home" USER="$usuario" LOGNAME="$usuario" \
    XDG_RUNTIME_DIR="/run/user/$(id -u "$usuario")" PATH=/usr/local/bin:/usr/bin:/bin "$@"
}

# --- 1. apps do Flathub ------------------------------------------------------
faltando=()
mapfile -t apps < <(grep -vE '^\s*(#|$)' /usr/share/kairos-play/flatpaks.txt)
for app in "${apps[@]}"; do
  flatpak info --system "$app" >/dev/null 2>&1 || faltando+=("$app")
done
if [ "${#faltando[@]}" -gt 0 ]; then
  echo "faltam apps: ${faltando[*]}"
  if nm-online -q -t 30 && curl -fsS --max-time 10 -o /dev/null https://dl.flathub.org/repo/summary.idx 2>/dev/null; then
    flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    flatpak remote-modify --system --enable flathub 2>/dev/null || true
    for app in "${faltando[@]}"; do
      aviso_tela "Kairos Play: instalando $app (só na primeira vez)..."
      flatpak install --system -y --noninteractive flathub "$app" || echo "falhou: $app"
    done
  else
    echo "sem internet agora: os apps que faltam ficam para o próximo boot com internet"
  fi
fi

# --- 2. script root + sudoers estreito ------------------------------------
aviso_tela "Kairos Play: preparando..."
install -D -m 755 -o root -g root "$KIT/root/kairos-play-atualizar-root" "$HELPER"
command -v restorecon >/dev/null && restorecon -F "$HELPER" >/dev/null 2>&1
tmp="$(mktemp)"
cat >"$tmp" <<SUDOEOF
# Gerado pelo primeiro boot do Kairos Play OS. Só este executável, sem NOPASSWD: ALL.
$usuario ALL=(root) NOPASSWD: $HELPER aplicar, $HELPER usar-desktop, $HELPER ping, $HELPER diagnostico
SUDOEOF
if visudo -cf "$tmp" >/dev/null 2>&1; then
  install -m 440 -o root -g root "$tmp" "$SUDOERS"
else
  echo "ERRO: sudoers gerado inválido; não gravei"
fi
rm -f "$tmp"

# --- 3a. sessão + login automático gravados direto (sem depender do usuário) --
install -D -m 755 -o root -g root "$KIT/kairos-play/sessao.sh" /usr/local/bin/kairos-play-sessao
mkdir -p /usr/local/share/wayland-sessions
cat >/usr/local/share/wayland-sessions/kairos-play.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Kairos Play
Comment=Tela de jogos Kairos Play (sem área de trabalho)
Exec=/usr/local/bin/kairos-play-sessao
DESK
chmod 644 /usr/local/share/wayland-sessions/kairos-play.desktop
mkdir -p /etc/sddm.conf.d /etc/plasmalogin.conf.d /etc/plasmalogin.d
cat >/etc/sddm.conf.d/zzz-kairos-play-autologin.conf <<CONF
# Gerado pelo primeiro boot do Kairos Play OS.
[Autologin]
User=$usuario
Session=$SESSAO
Relogin=true

[Wayland]
SessionDir=/usr/local/share/wayland-sessions,/usr/share/wayland-sessions
CONF
for f in /etc/plasmalogin.conf.d/zzz-kairos-play-plasmalogin.conf /etc/plasmalogin.d/zzz-kairos-play-plasmalogin.conf; do
  printf '%s\n' "# Gerado pelo primeiro boot do Kairos Play OS." "[Autologin]" "User=$usuario" "Session=$SESSAO" "Relogin=true" >"$f"
  chmod 644 "$f"
done
[ -f /etc/plasmalogin.conf ] && [ ! -f /etc/plasmalogin.conf.antes-do-kairos ] && cp /etc/plasmalogin.conf /etc/plasmalogin.conf.antes-do-kairos
python3 "$KIT/kairos-play/sddm_ini.py" autologin /etc/plasmalogin.conf "$usuario" "$SESSAO" - || echo "ERRO: plasmalogin.conf"
python3 "$KIT/kairos-play/sddm_ini.py" autologin /etc/sddm.conf "$usuario" "$SESSAO" || true
# Remove o assistente de primeiro usuário do Plasma, se tiver ficado (ele venceria o autologin).
rm -f /etc/plasmalogin.conf.d/99-plasma-setup.conf 2>/dev/null || true
if [ -f "$KIT/root/91-kairos-play-wifi.rules" ]; then
  install -D -m 644 "$KIT/root/91-kairos-play-wifi.rules" /etc/polkit-1/rules.d/91-kairos-play-wifi.rules
fi
command -v restorecon >/dev/null && restorecon -RF /usr/local/bin/kairos-play-sessao /usr/local/share/wayland-sessions \
  /etc/sddm.conf.d /etc/plasmalogin.conf /etc/plasmalogin.conf.d /etc/plasmalogin.d /etc/polkit-1/rules.d /etc/sudoers.d >/dev/null 2>&1
echo "autologin: $(grep -A3 '^\[Autologin\]' /etc/plasmalogin.conf | tr '\n' ' ')"

# --- 3b. parte do usuário: o próprio instalador do kit, modo do menu (sem senha) --
aviso_tela "Kairos Play: configurando a tela de jogos..."
como_usuario flatpak override --user --talk-name=org.freedesktop.Flatpak net.retrodeck.retrodeck || true
como_usuario flatpak override --user --filesystem="$home/.local/share/kairos-play:ro" io.mpv.Mpv || true
if command -v kwriteconfig6 >/dev/null 2>&1; then
  como_usuario kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
  como_usuario kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false
  como_usuario kwriteconfig6 --file ksplashrc --group KSplash --key Engine none
  for perfil in AC Battery LowBattery; do
    como_usuario kwriteconfig6 --file powerdevilrc --group "$perfil" --group SuspendAndShutdown --key AutoSuspendAction 0
    como_usuario kwriteconfig6 --file powerdevilrc --group "$perfil" --group Display --key TurnOffDisplayWhenIdle false
    como_usuario kwriteconfig6 --file powerdevilrc --group "$perfil" --group Display --key DimDisplayWhenIdle false
  done
fi
( cd "$home" && timeout 15m runuser -u "$usuario" -- env HOME="$home" USER="$usuario" LOGNAME="$usuario" \
    PATH=/usr/local/bin:/usr/bin:/bin bash "$KIT/instalar-gamestick.sh" --atualizar </dev/null )
rc=$?
echo "instalar-gamestick.sh --atualizar terminou com $rc"

# --- conferência final ------------------------------------------------------
ok=1
[ -x "$HELPER" ] && [ -f "$SUDOERS" ] || ok=0
grep -q "User=$usuario" /etc/plasmalogin.conf 2>/dev/null || ok=0
[ -f "$home/.local/share/kairos-play/kit/kairos-play/sessao.sh" ] || ok=0
flatpak info --system net.retrodeck.retrodeck >/dev/null 2>&1 || { echo "RetroDECK ainda não instalado"; ok=0; }
if grep -RqsE 'NOPASSWD:\s*ALL' /etc/sudoers.d/91-kairos-play-atualizar; then echo "ERRO: sudoers largo demais"; ok=0; fi
if [ "$ok" -eq 1 ]; then
  date '+%F %T' > "$ESTADO/primeiro-boot-ok"
  echo "PRONTO: liga direto no Kairos Play."
else
  echo "Ainda falta algo (veja acima). Tento de novo no próximo boot."
fi
exit 0
