FROM elixir:1.18-otp-28-alpine

# Install OpenSSH server
RUN apk add --no-cache openssh bash

# Configure SSH
RUN ssh-keygen -A
RUN sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
RUN sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config
RUN sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config

# Create test user
RUN adduser -D -s /bin/bash fusion_test && \
    echo "fusion_test:fusion_pass" | chpasswd

# Set up SSH key auth for test user
RUN mkdir -p /home/fusion_test/.ssh && \
    chmod 700 /home/fusion_test/.ssh && \
    chown fusion_test:fusion_test /home/fusion_test/.ssh

# Generate a test keypair (the public key will be in authorized_keys,
# the private key will be copied out for the test client)
RUN ssh-keygen -t ed25519 -f /home/fusion_test/.ssh/id_ed25519 -N "" && \
    cp /home/fusion_test/.ssh/id_ed25519.pub /home/fusion_test/.ssh/authorized_keys && \
    chmod 600 /home/fusion_test/.ssh/authorized_keys && \
    chown -R fusion_test:fusion_test /home/fusion_test/.ssh

# Ensure elixir/erl are on PATH for SSH sessions
RUN echo 'export PATH="/usr/local/bin:$PATH"' >> /home/fusion_test/.bashrc

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
