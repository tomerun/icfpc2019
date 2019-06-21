FROM crystallang/crystal:0.29.0

RUN apt update && \
	apt install -y curl python3 unzip

RUN curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py" && \
	python3 get-pip.py && \
	pip install awscli && \
	rm get-pip.py

COPY init.sh /root/init.sh

ENTRYPOINT ["/root/init.sh"] 
