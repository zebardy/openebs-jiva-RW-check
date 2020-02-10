FROM alpine:3.11

RUN apk add --no-cache curl jq grep bash

COPY check_volumes.sh /check_volumes.sh

ENTRYPOINT ["/check_volumes.sh"]
