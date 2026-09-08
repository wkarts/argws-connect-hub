# HUB development container. Uses the development HUB image from GHCR.
ARG HUB_DEVCONTAINER_IMAGE=ghcr.io/wkarts/argws-connect-hub:develop
FROM ${HUB_DEVCONTAINER_IMAGE}

USER root
WORKDIR /workspace
COPY . /workspace
CMD ["sleep", "infinity"]
