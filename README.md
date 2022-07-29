# telegram
redmine plugin for telegram

Compatibility
-------------
* Redmine 4.0 or higher


  Installation
----------------------
* Clone or [download](https://github.com/apsmir/telegram/archive/refs/heads/main.zip) this repo into your **redmine_root/plugins/** folder

```
$ git clone https://github.com/apsmir/telegram.git
```
* install gem from root redmine
```
$ bundle install
```
* set rigths
```
$ cd plugins/telegram
$ chmod +x start_poller.sh
$ chmod +x stop_poller.sh
```
* Restart Redmine
* In Admin panel (e.g. http://localhost:3000/settings/plugin/telegram) set parameters
  * Enabled
  * Bot Token 	
  * Bot Username
* Run Telegram poller
```
$ ./start_poller.sh
```