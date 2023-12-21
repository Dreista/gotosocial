# syntax=docker/dockerfile:1.3
# Dockerfile reference: https://docs.docker.com/engine/reference/builder/

# stage 1: generate up-to-date swagger.yaml to put in the final container
FROM --platform=${BUILDPLATFORM} golang:1.21-alpine AS swagger

RUN \
    ### Installs goswagger for building swagger definitions inside this container
    go install "github.com/go-swagger/go-swagger/cmd/swagger@v0.30.5" && \
    # Makes swagger executable
    chmod +x /go/bin/swagger

COPY go.mod /go/src/github.com/superseriousbusiness/gotosocial/go.mod
COPY go.sum /go/src/github.com/superseriousbusiness/gotosocial/go.sum
COPY cmd /go/src/github.com/superseriousbusiness/gotosocial/cmd
COPY internal /go/src/github.com/superseriousbusiness/gotosocial/internal

WORKDIR /go/src/github.com/superseriousbusiness/gotosocial
RUN /go/bin/swagger generate spec -o /go/src/github.com/superseriousbusiness/gotosocial/swagger.yaml --scan-models

# stage 2: generate the web/assets/dist bundles
FROM --platform=${BUILDPLATFORM} node:18-alpine AS bundler

COPY web web
RUN yarn --cwd ./web/source install && \
    yarn --cwd ./web/source ts-patch install && \
    yarn --cwd ./web/source build   && \
    rm -rf ./web/source

# stage 3: build the executor container
FROM --platform=${TARGETPLATFORM} alpine:3.17.2 as executor

# set up gotosocial user:group
ARG GTS_UID=1000
ARG GTS_GID=1000
RUN addgroup -g $GTS_GID -S gotosocial && \
    adduser -S -H -u $GTS_UID -G gotosocial gotosocial

# install setpriv for running as non-root, and shadow for usermod/groupmod
RUN apk add --no-cache setpriv shadow

# copy entrypoint script
COPY entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/entrypoint.sh

# switch to non-root user:group for GtS
USER gotosocial:gotosocial

# Because we're doing multi-arch builds we can't easily do `RUN mkdir [...]`
# but we can hack around that by having docker's WORKDIR make the dirs for
# us, as the user created above.
#
# See https://docs.docker.com/engine/reference/builder/#workdir
#
# First make sure storage exists + is owned by gotosocial:gotosocial, then
# go back to just /gotosocial, where we'll run from
WORKDIR "/gotosocial/storage"
WORKDIR "/gotosocial"

# copy the dist binary created by goreleaser or build.sh
COPY --chown=gotosocial:gotosocial gotosocial /gotosocial/gotosocial

# copy over the web directories with templates, assets etc
COPY --chown=gotosocial:gotosocial --from=bundler web /gotosocial/web
COPY --chown=gotosocial:gotosocial --from=swagger /go/src/github.com/superseriousbusiness/gotosocial/swagger.yaml web/assets/swagger.yaml

# switch back to root for entrypoint
USER root:root

VOLUME [ "/gotosocial/storage" ]
ENTRYPOINT [ "entrypoint.sh" ]
CMD [ "/gotosocial/gotosocial", "server", "start" ]
