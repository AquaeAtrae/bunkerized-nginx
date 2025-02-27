# Integrations

## Docker

<figure markdown>
  ![Overwiew](assets/img/integration-docker.svg){ align=center }
  <figcaption>Docker integration</figcaption>
</figure>

Using BunkerWeb as a [Docker](https://www.docker.com/) container is a quick and easy way to test and use it as long as you are familiar with the Docker technology.

We provide ready to use prebuilt images for x64, x86, armv7 and arm64 platforms on [Docker Hub](https://hub.docker.com/r/bunkerity/bunkerweb) :

```shell
docker pull bunkerity/bunkerweb:1.4.0
```

Alternatively, you can build the Docker images directly from the [source](https://github.com/bunkerity/bunkerweb) (and take a coffee ☕ because it may be long depending on your hardware) :

```shell
git clone https://github.com/bunkerity/bunkerweb.git && \
cd bunkerweb && \
docker build -t my-bunkerweb .
```

Usage and configuration of the BunkerWeb container are based on :

- **Environment variables** to configure BunkerWeb and meet your use cases
- **Volume** to cache important data and mount custom configuration files
- **Networks** to expose ports for clients and connect to upstream web services

### Environment variables

Settings are passed to BunkerWeb using Docker environment variables. You can use the `-e` flag :

```shell
docker run \
	   ...
	   -e MY_SETTING=value \
	   -e "MY_OTHER_SETTING=value with spaces" \
	   ...
	   bunkerity/bunkerweb:1.4.0
```

Here is the docker-compose equivalent :

```yaml
...
services:
  mybunker:
    image: bunkerity/bunkerweb:1.4.0
    environment:
      - MY_SETTING=value
```

!!! info "Full list"
    For the complete list of environment variables, see the [settings section](/settings) of the documentation.

### Volume

A volume is used to share data with BunkerWeb and store persistent data like certificates, cached files, ...

The easiest way of managing the volume is by using a named one. You will first need to create it :

```shell
docker volume create bw-data
```

Once it's created, you can mount it on `/data` when running the container :

```shell
docker run \
	   ...
	   -v "${PWD}/bw-data:/data" \
	   ...
	   bunkerity/bunkerweb:1.4.0
```

Here is the docker-compose equivalent :

```yaml
...
services:
  mybunker:
    image: bunkerity/bunkerweb:1.4.0
    volumes:
      - bw-data:/data
...
volumes:
  bw-data:
```

!!! warning
    BunkerWeb runs as an **unprivileged user with UID 101 and GID 101** inside the container. The reason behind this is the security : in case a vulnerability is exploited, the attacker won't have full root (UID/GID 0) privileges.
    But there is a downside : if you use a **local folder for the persistent data**, you will need to **set the correct permissions** so the unprivileged user can write data to it. Something like that should do the trick :
    `shell mkdir bw-data && \ chown root:101 bw-data && \ chmod 770 bw-data `

Alternatively, if the folder already exists :

```shell
chown -R root:101 bw-data && \
chmod -R 770 bw-data
```

Mounting the folder :

```shell
docker run \
        ...
      -v ./bw-data:/data \
        ...
        bunkerity/bunkerweb:1.4.0
```

Here is the docker-compose equivalent :

```yaml

...
services:
  mybunker:
  image: bunkerity/bunkerweb:1.4.0
  volumes:
    - ./bw-data:/data
```

### Networks

The easiest way to connect BunkerWeb to web applications is by using Docker networks.

First of all, you will need to create a network :

```shell
docker network create mynetwork
```

Once it's created, you will need to connect the container to that network :

```shell
docker run \
       ...
	   --network mynetwork \
	   ...
	   bunkerity/bunkerweb:1.4.0
```

You will also need to do the same with your web application(s). Please note that the other containers are accessible using their name as the hostname.

Here is the docker-compose equivalent :

```yaml
...
services:
  mybunker:
    image: bunkerity/bunkerweb:1.4.0
    networks:
      - bw-net
...
networks:
  bw-net:
```

## Docker autoconf

<figure markdown>
  ![Overwiew](assets/img/integration-autoconf.svg){ align=center }
  <figcaption>Docker autoconf integration</figcaption>
</figure>

!!! info "Docker integration"
    The Docker autoconf integration is an "evolution" of the Docker one. Please read the [Docker integration section](#docker) first if needed.

The downside of using environment variables is that the container needs to be recreated each time there is an update which is not very convenient. To counter that issue, you can use another image called **autoconf** which will listen for Docker events and automatically reconfigure BunkerWeb in real-time without recreating the container.

Instead of defining environment variables for the BunkerWeb container, you simply add **labels** to your web applications containers and the **autoconf** will "automagically" take care of the rest.

!!! info "Multisite mode"
    The Docker autoconf integration implies the use of **multisite mode**. Please refer to the [multisite section](/concepts/#multisite-mode) of the documentation for more information.

First of all, you will need to create the data volume :

```shell
docker volume create bw-data
```

- One for sharing the persistent data, mounted on **/data**
- Another one for sharing the generated Nginx configurations, mounted on **/etc/nginx**

Then, you can create two networks (replace 10.20.30.0/24 with an unused subnet of your choice) :

```shell
docker network create --subnet 10.20.30.0/24 bw-autoconf && \
docker network create bw-services
```

- One for communication between **BunkerWeb** and **autoconf**
- Another one for communication between **BunkerWeb** and **web applications**

You can now create the BunkerWeb container with the `AUTOCONF_MODE=yes` setting and the `bunkerweb.AUTOCONF` label (replace 10.20.30.0/24 with the subnet specified before) :

```shell
docker run \
       -d \
       --name mybunker \
	   --network bw-autoconf \
	   -p 80:8080 \
	   -p 443:8443 \
	   -e AUTOCONF_MODE=yes \
	   -e MULTISITE=yes \
	   -e SERVER_NAME= \
	   -e "API_WHITELIST_IP=127.0.0.0/8 10.20.30.0/24" \
	   -l bunkerweb.AUTOCONF \
	   bunkerity/bunkerweb:1.4.0 && \

docker network connect bw-services mybunker
```

And the autoconf one :

```shell
docker run \
       -d \
	   --name myautoconf \
	   --network bw-autoconf \
	   -v bw-data:/data \
	   -v /var/run/docker.sock:/var/run/docker.sock:ro \
	   bunkerity/bunkerweb-autoconf:1.4.0
```

Here is the docker-compose equivalent for the BunkerWeb autoconf stack :

```yaml
version: '3'

services:

  mybunker:
    image: bunkerity/bunkerweb:1.4.0
    ports:
      - 80:8080
	  - 443:8443
    volumes:
      - bw-data:/data
    environment:
	  - MULTISITE=yes
      - SERVER_NAME=
      - API_WHITELIST_IP=127.0.0.0/8 10.20.30.0/24
    labels:
      - "bunkerweb.AUTOCONF"
    networks:
      - bw-autoconf
	  - bw-services

  myautoconf:
    image: bunkerity/bunkerweb-autoconf:1.4.0
    volumes:
      - bw-data:/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - bw-autoconf

volumes:
  bw-data:

networks:
  bw-autoconf:
    ipam:
      driver: default
      config:
        - subnet: 10.20.30.0/24
  bw-services:
    name: bw-services
```

Once the stack is setup, you can now create the web application container and add the settings as labels using the "bunkerweb." prefix in order to automatically setup BunkerWeb :

```shell
docker run \
       -d \
       --name myapp \
	   --network bw-services \
	   -l bunkerweb.MY_SETTING_1=value1 \
	   -l bunkerweb.MY_SETTING_2=value2 \
       ...
	   mywebapp:4.2
```

Here is the docker-compose equivalent :

```yaml
...

services:

  myapp:
	image: mywebapp:4.2
    networks:
      bw-services:
        aliases:
          - myapp
    labels:
      - "bunkerweb.MY_SETTING_1=value1"
	  - "bunkerweb.MY_SETTING_2=value2"

...

networks:
  bw-services:
    external:
      name: bw-services

...
```

## Swarm

<figure markdown>
  ![Overwiew](assets/img/integration-swarm.svg){ align=center }
  <figcaption>Docker Swarm integration</figcaption>
</figure>

!!! info "Docker autoconf"
    The Docker autoconf integration is similar of the Docker autoconf one (but with services instead of containers). Please read the [Docker autoconf integration section](#docker-autoconf) first if needed.

To automatically configure BunkerWeb instances, a special service, called **autoconf**, will be scheduled on a manager node. That service will listen for Docker Swarm events like service creation or deletion and automatically configure the **BunkerWeb instances** in real-time without downtime.

Like the [Docker autoconf integration](#docker-autoconf), configuration for web services is defined using labels starting with the special **bunkerweb.** prefix.

The recommended setup is to schedule the **BunkerWeb service** as a **global service** on all worker nodes and the **autoconf service** as a **single replicated service** on a manager node.

First of all, you will need to create two networks (replace 10.20.30.0/24 with an unused subnet of your choice) :

```shell
docker network create -d overlay --attachable --subnet 10.20.30.0/24 bw-autoconf && \
docker network create -d overlay --attachable bw-services
```

- One for communication between **BunkerWeb** and **autoconf**
- Another one for communication between **BunkerWeb** and **web applications**

You can now create the BunkerWeb service (replace 10.20.30.0/24 with the subnet specified before) :

```shell
docker service create \
       --name mybunker \
	   --mode global \
	   --constraint node.role==worker \
	   --network bw-autoconf \
	   --network bw-services \
	   -p published=80,target=8080,mode=host \
	   -p published=443,target=8443,mode=host \
	   -e SWARM_MODE=yes \
	   -e SERVER_NAME= \
	   -e MULTISITE=yes \
	   -e "API_WHITELIST_IP=127.0.0.0/8 10.20.30.0/24" \
	   -l bunkerweb.AUTOCONF \
	   bunkerity/bunkerweb:1.4.0
```

And the autoconf one :

```shell
docker service \
       create \
	   --name myautoconf \
	   --constraint node.role==manager \
	   --network bw-autoconf \
	   --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock,ro \
	   --mount type=volume,source=bw-data,destination=/data \
	   -e SWARM_MODE=yes \
	   bunkerity/bunkerweb-autoconf:1.4.0
```

Here is the docker-compose equivalent (using `docker stack deploy`) :

```yaml
version: '3.5'

services:

  mybunker:
    image: bunkerity/bunkerweb:1.4.0
    ports:
      - published: 80
        target: 8080
        mode: host
        protocol: tcp
      - published: 443
        target: 8443
        mode: host
        protocol: tcp
    environment:
      - SWARM_MODE=yes
      - SERVER_NAME=
      - MULTISITE=yes
      - API_WHITELIST_IP=127.0.0.0/8 10.20.30.0/24
    networks:
      - bw-autoconf
      - bw-services
    deploy:
      mode: global
      placement:
        constraints:
          - "node.role==worker"
      labels:
        - "bunkerweb.AUTOCONF"

  myautoconf:
    image: bunkerity/bunkerweb-autoconf:1.4.0
    environment:
      - SWARM_MODE=yes
    volumes:
      - bw-data:/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - bw-autoconf
    deploy:
      replicas: 1
      placement:
        constraints:
          - "node.role==manager"

networks:
  bw-autoconf:
    driver: overlay
    attachable: true
    name: bw-autoconf
	ipam:
	  config:
        - subnet: 10.20.30.0/24
  bw-services:
    driver: overlay
    attachable: true
    name: bw-services

volumes:
  bw-data:
```

Once the BunkerWeb Swarm stack is set up and running (see autoconf logs for more information), you can now deploy web applications in the cluster and use labels to dynamically configure BunkerWeb :

```shell
docker service \
       create \
       --name myapp \
       --network bw-services \
       -l bunkerweb.MY_SETTING_1=value1 \
       -l bunkerweb.MY_SETTING_2=value2 \
       ...
       mywebapp:4.2
```

Here is the docker-compose equivalent (using `docker stack deploy`) :

```yaml
...
services:
  myapp:
    image: mywebapp:4.2
    networks:
      - bw-services
    deploy:
      placement:
        constraints:
          - "node.role==worker"
      labels:
        - "bunkerweb.MY_SETTING_1=value1"
        - "bunkerweb.MY_SETTING_2=value2"
...
networks:
  bw-services:
    external:
      name: bw-services
```

## Kubernetes

<figure markdown>
  ![Overwiew](assets/img/integration-kubernetes.svg){ align=center }
  <figcaption>Kubernetes integration</figcaption>
</figure>

The autoconf acts as an [Ingress controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) and will configure the BunkerWeb instances according to the [Ingress resources](https://kubernetes.io/docs/concepts/services-networking/ingress/). It also monitors other Kubernetes objects like [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) for custom configurations.

The first step to install BunkerWeb on a Kubernetes cluster is to add a role and permissions on the cluster for the autoconf :

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cr-bunkerweb
rules:
- apiGroups: [""]
  resources: ["services", "pods", "configmaps"]
  verbs: ["get", "watch", "list"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "watch", "list"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-bunkerweb
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: crb-bunkerweb
subjects:
- kind: ServiceAccount
  name: sa-bunkerweb
  namespace: default
  apiGroup: ""
roleRef:
  kind: ClusterRole
  name: cr-bunkerweb
  apiGroup: rbac.authorization.k8s.io
```

The recommended way of deploying BunkerWeb is using a [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) which means each node in the cluster will run an instance of BunkerWeb :

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: bunkerweb
spec:
  selector:
    matchLabels:
      app: bunkerweb
  template:
    metadata:
      labels:
        app: bunkerweb
      # mandatory annotation
      annotations:
        bunkerweb.io/AUTOCONF: "yes"
    spec:
      containers:
      - name: bunkerweb
        image: bunkerity/bunkerweb
        securityContext:
          runAsUser: 101
          runAsGroup: 101
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        ports:
        - containerPort: 8080
          hostPort: 80
        - containerPort: 8443
          hostPort: 443
        env:
        - name: KUBERNETES_MODE
          value: "yes"
        # replace with your DNS resolvers
        # e.g. : kube-dns.kube-system.svc.cluster.local
        - name: DNS_RESOLVERS
          value: "coredns.kube-system.svc.cluster.local"
        - name: USE_API
          value: "yes"
        # 10.0.0.0/8 is the cluster internal subnet
        - name: API_WHITELIST_IP
          value: "127.0.0.0/8 10.0.0.0/8"
        - name: SERVER_NAME
          value: ""
        - name: MULTISITE
          value: "yes"
        livenessProbe:
          exec:
            command:
            - /opt/bunkerweb/helpers/healthcheck.sh
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 1
          failureThreshold: 3
        readinessProbe:
          exec:
            command:
            - /opt/bunkerweb/helpers/healthcheck.sh
          initialDelaySeconds: 30
          periodSeconds: 1
          timeoutSeconds: 1
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: svc-bunkerweb
spec:
  clusterIP: None
  selector:
    app: bunkerweb
```

In order to store persistent data, you will need a [PersistentVolumeClaim](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-bunkerweb
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Now, you can start the autoconf as a single replica [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bunkerweb-controller
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: bunkerweb-controller
  template:
    metadata:
      labels:
        app: bunkerweb-controller
    spec:
      serviceAccountName: sa-bunkerweb
      volumes:
      - name: vol-bunkerweb
        persistentVolumeClaim:
          claimName: pvc-bunkerweb
      containers:
      - name: bunkerweb-controller
        image: bunkerity/bunkerweb-autoconf
        imagePullPolicy: Always
        env:
        - name: KUBERNETES_MODE
          value: "yes"
        volumeMounts:
        - name: vol-bunkerweb
          mountPath: /data
```

Once the BunkerWeb Kubernetes stack is setup and running (see autoconf logs for more information), you can now deploy web applications in the cluster and declare your Ingress resource. Please note that [settings](/settings) need to be set as annotations for the Ingress resource with the special value **bunkerweb.io** for the domain part :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress
  annotations:
	bunkerweb.io/MY_SETTING_1: "value1"
	bunkerweb.io/MY_SETTING_2: "value2"
spec:
  rules:
...
```

## Linux

<figure markdown>
  ![Overwiew](assets/img/integration-linux.svg){ align=center }
  <figcaption>Linux integration</figcaption>
</figure>

List of supported Linux distros :

- Debian 11 "Bullseye"
- Ubuntu 22.04 "Jammy"
- Fedora 36
- CentOS Stream 8

Please note that you will need to **install NGINX 1.20.2 before BunkerWeb**. The installation is not covered in this documentation but you need to use prebuilt packages from the NGINX official repository as described [here](https://nginx.org/en/linux_packages.html). If you are on Fedora, you can use the prebuilt packages from the Fedora repository.

Repositories of Linux packages for BunkerWeb are available on [PackageCloud](https://packagecloud.io/bunkerity/bunkerweb), they provide a bash script to automatically add and trust the repository (but you can also follow the [manual installation](https://packagecloud.io/bunkerity/bunkerweb/install) instructions if you prefer) :

=== "Debian"

    ```shell
    curl -s https://packagecloud.io/install/repositories/bunkerity/bunkerweb/script.deb.sh | sudo bash && \
	apt update && \
	apt install -y bunkerweb
    ```

=== "Ubuntu"

    ```shell
    curl -s https://packagecloud.io/install/repositories/bunkerity/bunkerweb/script.deb.sh | sudo bash && \
	apt update && \
	apt install -y bunkerweb
    ```

=== "Fedora"

    ```shell
    curl -s https://packagecloud.io/install/repositories/bunkerity/bunkerweb/script.rpm.sh | sudo bash && \
	dnf check-update && \
	dnf install -y bunkerweb
    ```

=== "CentOS Stream"

    ```shell
	dnf install -y epel-release && \
    curl -s https://packagecloud.io/install/repositories/bunkerity/bunkerweb/script.rpm.sh | sudo bash && \
	dnf check-update && \
	dnf install -y bunkerweb
    ```

Configuration of BunkerWeb is done by editing the `/opt/bunkerweb/variables.env` file :

```conf
MY_SETTING_1=value1
MY_SETTING_2=value2
...
```

BunkerWeb is managed using systemctl :

- Check BunkerWeb status : `systemctl status bunkerweb`
- Reload the configuration : `systemctl reload bunkerweb`
- Start it if it's stopped : `systemctl start bunkerweb`
- Stop it if it's started : `systemctl stop bunkerweb`
- And restart : `systemctl restart bunkerweb`
