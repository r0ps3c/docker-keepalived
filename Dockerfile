FROM alpine
RUN \
	apk --no-cache add keepalived && \
	rm -rf /var/cache/apk/*
ENTRYPOINT ["/usr/sbin/keepalived", "-l", "-n"]
