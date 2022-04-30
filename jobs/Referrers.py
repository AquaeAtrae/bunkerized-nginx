from Job import Job

class Referrers(Job) :

	def __init__(self, redis_host=None, copy_cache=False) :
		name = "referrers"
		data = ["https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/master/_generator_lists/bad-referrers.list"]
		filename = "referrers.list"
		type = "line"
		regex = r"^.+$"
		redis_ex = 86400
		super().__init__(name, data, filename, redis_host=redis_host, redis_ex=redis_ex, type=type, regex=regex, copy_cache=copy_cache)

	def _edit(self, chunk) :
		return [chunk.replace(".", "%.").replace("-", "%-")]
