import traceback

from docker import DockerClient

from Controller import Controller
from logger import log

class DockerController(Controller) :

    def __init__(self, docker_host) :
        super().__init__("docker")
        self.__client = DockerClient(base_url=docker_host)

    def _get_controller_instances(self) :
        return self.__client.containers.list(filters={"label" : "bunkerweb.AUTOCONF"})
        
    def _to_instances(self, controller_instance) :
        instance = {}
        instance["name"] = controller_instance.name
        instance["hostname"] = controller_instance.name
        instance["health"] = controller_instance.status == "running" and controller_instance.attrs["State"]["Health"]["Status"] == "healthy"
        instance["env"] = {}
        for env in controller_instance.attrs["Config"]["Env"] :
            variable = env.split("=")[0]
            if variable in ["PATH", "NGINX_VERSION", "NJS_VERSION", "PKG_RELEASE"] :
                continue
            value = env.replace(variable + "=", "", 1)
            instance["env"][variable] = value
        server_name = []
        for controller_service in self._get_controller_services() :
            if "bunkerweb.SERVER_NAME" in controller_service.labels :
                server_name.append(controller_service.labels["bunkerweb.SERVER_NAME"].split(" ")[0])
        instance["env"]["SERVER_NAME"] = " ".join(server_name)
        return [instance]

    def _get_controller_services(self) :
        return self.__client.containers.list(filters={"label" : "bunkerweb.SERVER_NAME"})
        
    def _to_services(self, controller_service) :
        service = {}
        for variable, value in controller_service.labels.items() :
            if not variable.startswith("bunkerweb.") :
                continue
            service[variable.replace("bunkerweb.", "", 1)] = value
        return [service]

    def get_configs(self) :
        raise("get_configs is not supported with DockerController")

    def apply_config(self) :
        return self._config.apply(self._instances, self._services, configs=self._configs)

    def process_events(self) :
        for event in self.__client.events(decode=True, filters={"type": "container"}) :
            self._instances = self.get_instances()
            self._services = self.get_services()
            if not self._config.update_needed(self._instances, self._services) :
                continue
            log("DOCKER-CONTROLLER", "ℹ️", "Catched docker event, deploying new configuration ...")
            try :
                ret = self.apply_config()
                if not ret :
                    log("DOCKER-CONTROLLER", "❌", "Error while deploying new configuration")
                else :
                    log("DOCKER-CONTROLLER", "ℹ️", "Successfully deployed new configuration 🚀")
            except :
                log("DOCKER-CONTROLLER", "❌", "Exception while deploying new configuration :")
                print(traceback.format_exc())