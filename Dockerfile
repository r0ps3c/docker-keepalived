FROM alpine:3.23

RUN \
	apk --no-cache add keepalived=2.3.4-r3 bash && \
	apk upgrade --no-cache && \
	rm -rf /var/cache/apk/*

ENTRYPOINT ["/usr/sbin/keepalived", "-l", "-n"]
