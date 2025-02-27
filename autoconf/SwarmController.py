from traceback import format_exc
from threading import Thread, Lock
from docker import DockerClient
from logger import log
from base64 import b64decode

from Controller import Controller

class SwarmController(Controller) :

    def __init__(self, docker_host) :
        super().__init__("swarm")
        self.__client = DockerClient(base_url=docker_host)
        self.__internal_lock = Lock()
        
    def _get_controller_instances(self) :
        return self.__client.services.list(filters={"label" : "bunkerweb.AUTOCONF"})
    
    def _to_instances(self, controller_instance) :
        instances = []
        instance_env = {}
        for env in controller_instance.attrs["Spec"]["TaskTemplate"]["ContainerSpec"]["Env"] :
            variable = env.split("=")[0]
            value = env.replace(variable + "=", "", 1)
            instance_env[variable] = value
        for task in controller_instance.tasks() :
            instance = {}
            instance["name"] = task["ID"]
            instance["hostname"] = controller_instance.name + "." + task["NodeID"] + "." + task["ID"]
            instance["health"] = task["Status"]["State"] == "running"
            instance["env"] = instance_env
            instances.append(instance)
        return instances

    def _get_controller_services(self) :
        return self.__client.services.list(filters={"label" : "bunkerweb.SERVER_NAME"})
        
    def _to_services(self, controller_service) :
        service = {}
        for variable, value in controller_service.attrs["Spec"]["Labels"].items() :
            if not variable.startswith("bunkerweb.") :
                continue
            service[variable.replace("bunkerweb.", "", 1)] = value
        return [service]

    def get_configs(self) :
        configs = {}
        for config_type in self._supported_config_types :
            configs[config_type] = {}
        for config in self.__client.configs.list(filters={"label" : "bunkerweb.CONFIG_TYPE"}) :
            config_type = config.attrs["Spec"]["Labels"]["bunkerweb.CONFIG_TYPE"]
            config_name = config.name
            if config_type not in self._supported_config_types :
                log("SWARM-CONTROLLER", "⚠️", "Ignoring unsupported CONFIG_TYPE " + config_type + " for Config " + config_name)
                continue
            config_site = ""
            if "bunkerweb.CONFIG_SITE" in config.attrs["Spec"]["Labels"] :
                config_site = config.attrs["Spec"]["Labels"]["bunkerweb.CONFIG_SITE"] + "/"
            configs[config_type][config_site + config_name] = b64decode(config.attrs["Spec"]["Data"])
        return configs

    def apply_config(self) :
        self._config.stop_scheduler()
        ret = self._config.apply(self._instances, self._services, configs=self._configs)
        self._config.start_scheduler()
        return ret
                
    def __event(self, event_type) :
        for event in self.__client.events(decode=True, filters={"type": event_type}) :
            self.__internal_lock.acquire()
            self._instances = self.get_instances()
            self._services = self.get_services()
            self._configs = self.get_configs()
            if not self._config.update_needed(self._instances, self._services, configs=self._configs) :
                self.__internal_lock.release()
                continue
            log("SWARM-CONTROLLER", "ℹ️", "Catched Swarm event, deploying new configuration ...")
            try :
                ret = self.apply_config()
                if not ret :
                    log("SWARM-CONTROLLER", "❌", "Error while deploying new configuration ...")
                else :
                    log("SWARM-CONTROLLER", "ℹ️", "Successfully deployed new configuration 🚀")
            except :
                log("SWARM-CONTROLLER", "❌", "Exception while deploying new configuration :")
                print(format_exc())
            self.__internal_lock.release()
    
    def process_events(self) :
        event_types = ["service", "config"]
        threads = []
        for event_type in event_types :
            threads.append(Thread(target=self.__event, args=(event_type,)))
        for thread in threads :
            thread.start()
        for thread in threads :
            thread.join()