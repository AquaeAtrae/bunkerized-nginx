#!/usr/bin/python3

import subprocess, shutil, os, traceback, requests, time, dns.resolver, io, tarfile

import Controller

from logger import log

CONFIGS = {
	"conf": "/etc/nginx",
	"letsencrypt": "/etc/letsencrypt",
	"http": "/http-confs",
	"server": "/server-confs",
	"modsec": "/modsec-confs",
	"modsec-crs": "/modsec-crs-confs",
	"acme": "/acme-challenge"
}

class Config :

	def __init__(self, type, api_uri, http_port="8080") :
		self.__type = type
		self.__api_uri = api_uri
		self.__http_port = http_port

	def __jobs(self) :
		log("config", "INFO", "starting jobs ...")
		proc = subprocess.run(["/bin/su", "-c", "/opt/bunkerized-nginx/entrypoint/jobs.sh", "nginx"], capture_output=True)
		stdout = proc.stdout.decode("ascii")
		stderr = proc.stderr.decode("ascii")
		if len(stdout) > 1 :
			log("config", "INFO", "jobs stdout :\n" + stdout)
		if stderr != "" :
			log("config", "ERROR", "jobs stderr :\n" + stderr)
		if proc.returncode != 0 :
			log("config", "ERROR", "jobs error (return code = " + str(proc.returncode) + ")")
			return False
		return True

	def gen(self, env) :
		try :
			# Write environment variables to a file
			with open("/tmp/variables.env", "w") as f :
				for k, v in env.items() :
					f.write(k + "=" + v + "\n")

			# Call the generator
			proc = subprocess.run(["/bin/su", "-c", "/opt/bunkerized-nginx/gen/main.py --settings /opt/bunkerized-nginx/settings.json --templates /opt/bunkerized-nginx/confs --output /etc/nginx --variables /tmp/variables.env", "nginx"], capture_output=True)

			# Print stdout/stderr
			stdout = proc.stdout.decode("ascii")
			stderr = proc.stderr.decode("ascii")
			if len(stdout) > 1 :
				log("config", "INFO", "generator output : " + stdout)
			if stderr != "" :
				log("config", "ERROR", "generator error : " + stderr)

			# We're done
			if proc.returncode == 0 :
				if self.__type == Controller.Type.SWARM or self.__type == Controller.Type.KUBERNETES :
					return self.__jobs()
				return True
			log("config", "ERROR", "error while generating config (return code = " + str(proc.returncode) + ")")

		except Exception as e :
			log("config", "ERROR", "exception while generating site config : " + traceback.format_exc())
		return False

	def reload(self, instances) :
		ret = True
		if self.__type == Controller.Type.DOCKER :
			for instance in instances :
				try :
					instance.kill("SIGHUP")
				except :
					ret = False
		elif self.__type == Controller.Type.SWARM or self.__type == Controller.Type.KUBERNETES :
			ret = self.__api_call(instances, "/reload")
		return ret

	def send(self, instances, files="all") :
		ret = True
		fail = False
		for name, path in CONFIGS.items() :
			if files != "all" and name != files :
				continue
			file = self.__tarball(path)
			if not self.__api_call(instances, "/" + name, file=file) :
				log("config", "ERROR", "can't send config " + name + " to instance(s)")
				fail = True
			file.close()
		if fail :
			ret = False
		return ret

	def stop_temp(self, instances) :
		return self.__api_call(instances, "/stop-temp")

	def __tarball(self, path) :
		file = io.BytesIO()
		with tarfile.open(mode="w:gz", fileobj=file) as tar :
			tar.add(path, arcname=".")
		file.seek(0, 0)
		return file

	def __ping(self, instances) :
		return self.__api_call(instances, "/ping")

	def wait(self, instances) :
		ret = True
		if self.__type == Controller.Type.DOCKER :
			ret = self.__wait_docker(instances)
		elif self.__type == Controller.Type.SWARM or self.__type == Controller.Type.KUBERNETES :
			ret = self.__wait_api(instances)
		return ret

	def __wait_docker(self, instances) :
		all_healthy = False
		i = 0
		while i < 120 :
			one_not_healthy = False
			for instance in instances :
				instance.reload()
				if instance.attrs["State"]["Health"]["Status"] != "healthy" :
					one_not_healthy = True
					break
			if not one_not_healthy :
				all_healthy = True
				break
			time.sleep(1)
			i += 1
		return all_healthy

	def __wait_api(self, instances) :
		try :
			with open("/etc/nginx/autoconf", "w") as f :
				f.write("ok")
			i = 1
			started = False
			while i <= 10 :
				time.sleep(i)
				if self.__ping(instances) :
					started = True
					break
				i = i + 1
				log("config", "INFO", "waiting " + str(i) + " seconds before retrying to contact bunkerized-nginx instances")
			if started :
				log("config", "INFO", "bunkerized-nginx instances started")
				return True
			else :
				log("config", "ERROR", "bunkerized-nginx instances are not started")
		except Exception as e :
			log("config", "ERROR", "exception while waiting for bunkerized-nginx instances : " + traceback.format_exc())
		return False

	def __api_call(self, instances, path, file=None) :
		ret = True
		nb = 0
		urls = []
		if self.__type == Controller.Type.SWARM :
			for instance in instances :
				name = instance.name
				try :
					dns_result = dns.resolver.query("tasks." + name)
					for ip in dns_result :
						urls.append("http://" + ip.to_text() + ":" + self.__http_port + self.__api_uri + path)
				except :
					ret = False
		elif self.__type == Controller.Type.KUBERNETES :
			for instance in instances :
				name = instance.metadata.name
				try :
					dns_result = dns.resolver.query(name + "." + instance.metadata.namespace + ".svc.cluster.local")
					for ip in dns_result :
						urls.append("http://" + ip.to_text() + ":" + self.__http_port + self.__api_uri + path)
				except :
					ret = False

		for url in urls :
			req = None
			try :
				if file == None :
					req = requests.post(url)
				else :
					file.seek(0, 0)
					req = requests.post(url, files={'file': file})
			except :
				pass
			if req and req.status_code == 200 and req.text == "ok" :
				log("config", "INFO", "successfully sent API order to " + url)
				nb += 1
			else :
				log("config", "INFO", "failed API order to " + url)
				ret = False
		return ret and nb > 0
