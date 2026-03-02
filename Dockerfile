FROM alpine:3.23

RUN \
	apk --no-cache add keepalived=2.3.4-r2 bash && \
	rm -rf /var/cache/apk/*

ENTRYPOINT ["/usr/sbin/keepalived", "-l", "-n"]
