from os.path import isfile
from dotenv import dotenv_values
from docker import DockerClient
from kubernetes import client, config

from ApiCaller import ApiCaller
from API import API

class CLI(ApiCaller) :

    def __init__(self) :
        self.__variables = dotenv_values("/etc/nginx/variables.env")
        self.__integration = self.__detect_integration()
        super().__init__(self.__get_apis())

    def __detect_integration(self) :
        ret = "unknown"
        distrib = ""
        if isfile("/etc/os-release") :
            with open("/etc/os-release", "r") as f :
                if "Alpine" in f.read() :
                    distrib = "alpine"
                else :
                    distrib = "other"
        # Docker case
        if distrib == "alpine" and isfile("/usr/sbin/nginx") :
            return "docker"
        # Linux case
        if distrib == "other" :
            return "linux"
        # Swarm case
        if self.__variables["SWARM_MODE"] == "yes" :
            return "swarm"
        # Kubernetes case
        if self.__variables["KUBERNETES_MODE"] == "yes" :
            return "kubernetes"
        # Autoconf case
        if distrib == "alpine" :
            return "autoconf"
        
        raise Exception("can't detect integration")

    def __get_apis(self) :
        # Docker case
        if self.__integration == "docker" :
            return [API("http://127.0.0.1:" + self.__variables["API_HTTP_PORT"], host=self.__variables["API_SERVER_NAME"])]

        # Autoconf case
        if self.__integration == "autoconf" :
            docker_client = DockerClient()
            apis = []
            for container in self.__client.containers.list(filters={"label" : "bunkerweb.AUTOCONF"}) :
                port = "5000"
                host = "bwapi"
                for env in container.attrs["Config"]["Env"] :
                    if env.startswith("API_HTTP_PORT=") :
                        port = env.split("=")[1]
                    elif env.startswith("API_SERVER_NAME=") :
                        host = env.split("=")[1]
                apis.append(API("http://" + container.name + ":" + port, host=host))
            return apis

        # Swarm case
        if self.__integration == "swarm" :
            docker_client = DockerClient()
            apis = []
            for service in self.__client.services.list(filters={"label" : "bunkerweb.AUTOCONF"}) :
                port = "5000"
                host = "bwapi"
                for env in service.attrs["Spec"]["TaskTemplate"]["ContainerSpec"]["Env"] :
                    if env.startswith("API_HTTP_PORT=") :
                        port = env.split("=")[1]
                    elif env.startswith("API_SERVER_NAME=") :
                        host = env.split("=")[1]
                for task in service.tasks() :
                    apis.append(API("http://" + service.name + "." + task["NodeID"] + "." + task["ID"] + ":" + port, host=host))
            return apis
        
        # Kubernetes case
        if self.__integration == "kubernetes" :
            config.load_incluster_config()
            corev1 = client.CoreV1Api()
            apis = []
            for pod in corev1.list_pod_for_all_namespaces(watch=False).items :
                if pod.metadata.annotations != None and "bunkerweb.io/AUTOCONF" in pod.metadata.annotations and pod.status.pod_ip :
                    port = "5000"
                    host = "bwapi"
                    for env in pod.spec.containers[0].env :
                        if env.name == "API_HTTP_PORT" :
                            port = env.value
                        elif env.name == "API_SERVER_NAME" :
                            host = env.value
                    apis.append(API("http://" + pod.status.pod_ip + ":" + port, host=host))
            return apis
        
    def unban(self, ip) :
        if self._send_to_apis("POST", "/unban", data={"ip": ip}) :
            return True, "IP " + ip + " has been unbanned"
        return False, "error"
