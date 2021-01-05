package actionScripts.plugins.git.utils
{
	import actionScripts.utils.FileUtils;

	import flash.filesystem.File;

	public class GitUtils
	{
		public static const GIT_EXPECT_PATH:File = File.applicationStorageDirectory.resolvePath("spawn/connectgit.exp");
		public static const GIT_EXPECT		: XML = <root><![CDATA[
			#!/bin/sh

			log_user 0
			puts -nonewline "Enter password (exp): "
			flush stdout
			gets stdin password
			set newPromptA ".*password:"
			set newPromptB "Password.*:"

			log_user 1
			spawn %GIT_COMMAND%

			expect {
				-re $newPromptA {
					send "$password\r"
				} -re $newPromptB {
					send "$password\r"
				}
			}

			interact
			]]></root>

		public static function getCalculatedRemotePathWithAuth(initialPath:String, username:String, password:String=null):String
		{
			var calculatedURL:String = initialPath;
			if (calculatedURL.indexOf("@") != -1)
			{
				calculatedURL = calculatedURL.replace(
						calculatedURL.substring(0, calculatedURL.indexOf("@") + 1),
						""
				);
			}

			return (calculatedURL = "https://"+ username + (password ? ":"+ password : "") +"@"+ calculatedURL);
		}

		public static function getCalculatedRemotePathWithoutPassword(initialPath:String, username:String):String
		{
			var calculatedURL:String = initialPath;
			if (calculatedURL.indexOf("@") != -1)
			{
				calculatedURL = calculatedURL.replace(
						calculatedURL.substring(0, calculatedURL.indexOf("@") + 1),
						""
				);
			}

			return (calculatedURL = "https://"+ username +"@"+ calculatedURL);
		}

		public static function writeExpOnMacAuthentication(withCommand:String, successHandler:Function=null):String
		{
			var tmpExp:String = GIT_EXPECT.valueOf().toString();
			tmpExp = tmpExp.replace("%GIT_COMMAND%", withCommand);

			FileUtils.writeToFileAsync(GIT_EXPECT_PATH, tmpExp, successHandler);

			return '';
		}
	}
}
