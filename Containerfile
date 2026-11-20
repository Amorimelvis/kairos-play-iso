# Kairos Play OS - imagem bootc/OCI baseada no Bazzite (KDE, Intel/AMD, sem NVIDIA).
# Construída no GitHub Actions (.github/workflows/build.yml). Sem ROMs comerciais, sem BIOS, sem segredos.

# Versão do kit Kairos Play que entra na imagem. "latest" = último release de
# Amorimelvis/kairos-play-atualizacoes no momento do build.
ARG KIT_TAG=latest
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable

FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM ${BASE_IMAGE}
ARG KIT_TAG

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    KIT_TAG="${KIT_TAG}" /ctx/build.sh

LABEL org.opencontainers.image.title="kairos-play-os" \
      org.opencontainers.image.description="Kairos Play: Bazzite que liga direto na tela de jogos Kairos" \
      org.opencontainers.image.vendor="Kairos Software"

RUN bootc container lint
