# HUB development container.
# Uses the already-published HUB application image from GHCR as its parent.
ARG HUB_DEVCONTAINER_IMAGE=ghcr.io/wkarts/hub:latest
FROM ${HUB_DEVCONTAINER_IMAGE}

USER root
WORKDIR /workspace
COPY . /workspace

CMD ["sleep", "infinity"]
