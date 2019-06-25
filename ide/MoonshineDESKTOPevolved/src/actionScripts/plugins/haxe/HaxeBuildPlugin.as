////////////////////////////////////////////////////////////////////////////////
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
// http://www.apache.org/licenses/LICENSE-2.0 
// 
// Unless required by applicable law or agreed to in writing, software 
// distributed under the License is distributed on an "AS IS" BASIS, 
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and 
// limitations under the License
// 
// No warranty of merchantability or fitness of any kind. 
// Use this software at your own risk.
// 
////////////////////////////////////////////////////////////////////////////////
package actionScripts.plugins.haxe
{
    import actionScripts.events.SettingsEvent;
    import actionScripts.events.StatusBarEvent;
    import actionScripts.plugin.core.compiler.HaxeBuildEvent;
    import actionScripts.plugin.haxe.hxproject.vo.HaxeProjectVO;
    import actionScripts.plugin.settings.ISettingsProvider;
    import actionScripts.plugin.settings.vo.AbstractSetting;
    import actionScripts.plugin.settings.vo.ISetting;
    import actionScripts.plugin.settings.vo.PathSetting;
    import actionScripts.plugins.build.ConsoleBuildPluginBase;
    import actionScripts.utils.HelperUtils;
    import actionScripts.utils.UtilsCore;
    import actionScripts.valueObjects.ComponentTypes;
    import actionScripts.valueObjects.ComponentVO;
    import actionScripts.valueObjects.ConstantsCoreVO;
    import actionScripts.valueObjects.ProjectVO;

    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.NativeProcessExitEvent;
    import flash.events.ProgressEvent;
    import actionScripts.factory.FileLocation;
    import actionScripts.events.ApplicationEvent;
    import flash.desktop.NativeProcess;
    import flash.desktop.NativeProcessStartupInfo;
    import flash.filesystem.File;

    public class HaxeBuildPlugin extends ConsoleBuildPluginBase implements ISettingsProvider
    {
		private var haxePathSetting:PathSetting;
		private var nodePathSetting:PathSetting;
		private var isProjectHasInvalidPaths:Boolean;
		private var isDebugging:Boolean;
		
        public function HaxeBuildPlugin()
        {
            super();
        }
		
		override protected function onProjectPathsValidated(paths:Array):void
		{
			if (paths)
			{
				isProjectHasInvalidPaths = true;
				error("Following path(s) are invalid or does not exists:\n"+ paths.join("\n"));
			}
		}

        override public function get name():String
        {
            return "Haxe Build Setup";
        }

        override public function get author():String
        {
            return ConstantsCoreVO.MOONSHINE_IDE_LABEL + " Project Team";
        }

        override public function get description():String
        {
            return "Haxe Build Plugin.";
        }

        public function get haxePath():String
        {
            return model ? model.haxePath : null;
        }

        public function set haxePath(value:String):void
        {
            if (model.haxePath != value)
            {
                model.haxePath = value;
            }
        }

        public function get nodePath():String
        {
            return model ? model.nodePath : null;
        }

        public function set nodePath(value:String):void
        {
            if (model.nodePath != value)
            {
                model.nodePath = value;
            }
        }

        public function getSettingsList():Vector.<ISetting>
        {
			onSettingsClose();
			haxePathSetting = new PathSetting(this, 'haxePath', 'Haxe Home', true, haxePath);
			haxePathSetting.addEventListener(AbstractSetting.PATH_SELECTED, onHaxeSDKPathSelected, false, 0, true);
            
			nodePathSetting = new PathSetting(this, 'nodePath', 'Node.js Home', true, nodePath);
			nodePathSetting.addEventListener(AbstractSetting.PATH_SELECTED, onNodePathSelected, false, 0, true);
			
			return Vector.<ISetting>([
				haxePathSetting,
                nodePathSetting
			]);
        }
		
		override public function onSettingsClose():void
		{
			if (haxePathSetting)
			{
				haxePathSetting.removeEventListener(AbstractSetting.PATH_SELECTED, onHaxeSDKPathSelected);
				haxePathSetting = null;
			}
		}
		
		private function onHaxeSDKPathSelected(event:Event):void
		{
			if (!haxePathSetting.stringValue) return;
			var tmpComponent:ComponentVO = HelperUtils.getComponentByType(ComponentTypes.TYPE_HAXE);
			if (tmpComponent)
			{
				var isValidSDKPath:Boolean = HelperUtils.isValidSDKDirectoryBy(ComponentTypes.TYPE_HAXE, haxePathSetting.stringValue, tmpComponent.pathValidation);
				if (!isValidSDKPath)
				{
					haxePathSetting.setMessage("Invalid path: Path must contain "+ tmpComponent.pathValidation +".", AbstractSetting.MESSAGE_CRITICAL);
				}
				else
				{
					haxePathSetting.setMessage(null);
				}
			}
		}
		
		private function onNodePathSelected(event:Event):void
		{
			if (!nodePathSetting.stringValue) return;
			var tmpComponent:ComponentVO = HelperUtils.getComponentByType(ComponentTypes.TYPE_NODE);
			if (tmpComponent)
			{
				var isValidSDKPath:Boolean = HelperUtils.isValidSDKDirectoryBy(ComponentTypes.TYPE_NODE, nodePathSetting.stringValue, tmpComponent.pathValidation);
				if (!isValidSDKPath)
				{
					nodePathSetting.setMessage("Invalid path: Path must contain "+ tmpComponent.pathValidation +".", AbstractSetting.MESSAGE_CRITICAL);
				}
				else
				{
					nodePathSetting.setMessage(null);
				}
			}
		}

        override public function activate():void
        {
            super.activate();

			dispatcher.addEventListener(HaxeBuildEvent.BUILD_AND_RUN, haxeBuildAndRunHandler);
			dispatcher.addEventListener(HaxeBuildEvent.BUILD_DEBUG, haxeBuildDebugHandler);
			dispatcher.addEventListener(HaxeBuildEvent.BUILD_RELEASE, haxeBuildReleaseHandler);
        }

        override public function deactivate():void
        {
            super.deactivate();

			dispatcher.removeEventListener(HaxeBuildEvent.BUILD_AND_RUN, haxeBuildAndRunHandler);
			dispatcher.removeEventListener(HaxeBuildEvent.BUILD_DEBUG, haxeBuildDebugHandler);
			dispatcher.removeEventListener(HaxeBuildEvent.BUILD_RELEASE, haxeBuildReleaseHandler);
        }
		
		private function haxeBuildAndRunHandler(event:Event):void
		{
            var project:HaxeProjectVO = model.activeProject as HaxeProjectVO;
            if (!project)
            {
                return;
            }
            if(project.isLime)
            {
                var projectFolder:FileLocation = project.folderLocation;
                if(project.targetPlatform == HaxeProjectVO.PLATFORM_HTML5)
                {
				    running = true;
                    isDebugging = true;
                    var processInfo:NativeProcessStartupInfo = new NativeProcessStartupInfo();
                    processInfo.executable = new File(UtilsCore.getNpxBinPath());
                    processInfo.arguments = new <String>[
                        "http-server",
                        "bin/html5/bin",
                        "-p",
                        "3000",
                        "-o"
                    ];
                    processInfo.workingDirectory = new File(projectFolder.fileBridge.nativePath);
                    nativeProcess = new NativeProcess();
                    addNativeProcessEventListeners();
                    nativeProcess.start(processInfo);
                    dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_DEBUG_STARTED, project.projectName, "Debug "));
                    dispatcher.addEventListener(StatusBarEvent.PROJECT_BUILD_TERMINATE, onProjectBuildTerminate, false, 0, true);
			        dispatcher.addEventListener(ApplicationEvent.APPLICATION_EXIT, onApplicationExit, false, 0, true);
                }
                else
                {
			        this.startDebug(new <String>[["\"" + UtilsCore.getLimeBinPath() + "\"", "test", project.targetPlatform, "-debug"].join(" ")], projectFolder);
                }
            }
            else
            {
                error("Haxe debug without Lime not implemented yet");
            }
		}
		
		private function haxeBuildDebugHandler(event:Event):void
		{
            var project:HaxeProjectVO = model.activeProject as HaxeProjectVO;
            if (!project)
            {
                return;
            }
            if(project.isLime)
            {
			    this.start(new <String>[["\"" + UtilsCore.getLimeBinPath() + "\"", "build", project.targetPlatform, "-debug"].join(" ")], model.activeProject.folderLocation);
            }
            else
            {
                error("Haxe build without Lime not implemented yet");
            }
		}
		
		private function haxeBuildReleaseHandler(event:Event):void
		{
            var project:HaxeProjectVO = model.activeProject as HaxeProjectVO;
            if (!project)
            {
                return;
            }
            if(project.isLime)
            {
			    this.start(new <String>[["\"" + UtilsCore.getLimeBinPath() + "\"", "build", project.targetPlatform, "-final"].join(" ")], model.activeProject.folderLocation);
            }
            else
            {
                error("Haxe build without Lime not implemented yet");
            }
		}

		override public function start(args:Vector.<String>, buildDirectory:*):void
		{
            if (nativeProcess.running && running)
            {
                warning("Build is running. Wait for finish...");
                return;
            }

            if (!haxePath)
            {
                error("Specify path to Haxe folder.");
                stop(true);
                dispatcher.dispatchEvent(new SettingsEvent(SettingsEvent.EVENT_OPEN_SETTINGS, "actionScripts.plugins.haxe::HaxeBuildPlugin"));
                return;
            }
			
            isDebugging = false;
            warning("Starting Haxe build...");

			super.start(args, buildDirectory);
			
            print("Haxe build directory: %s", buildDirectory.fileBridge.nativePath);
            print("Command: %s", args.join(" "));

            var project:ProjectVO = model.activeProject;
            if (project)
            {
                dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_STARTED, project.projectName, "Building "));
                dispatcher.addEventListener(StatusBarEvent.PROJECT_BUILD_TERMINATE, onProjectBuildTerminate);
            }
		}
        
        public function startDebug(args:Vector.<String>, buildDirectory:*):void
		{
            if (nativeProcess.running && running)
            {
                warning("Build is running. Wait for finish...");
                return;
            }

            if (!haxePath)
            {
                error("Specify path to Haxe folder.");
                stop(true);
                dispatcher.dispatchEvent(new SettingsEvent(SettingsEvent.EVENT_OPEN_SETTINGS, "actionScripts.plugins.haxe::HaxeBuildPlugin"));
                return;
            }

            isDebugging = true;
			super.start(args, buildDirectory);
			
            print("Command: %s", args.join(" "));

            var project:ProjectVO = model.activeProject;
            if (project)
            {
                dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_DEBUG_STARTED, project.projectName, "Debug "));
                dispatcher.addEventListener(StatusBarEvent.PROJECT_BUILD_TERMINATE, onProjectBuildTerminate, false, 0, true);
			    dispatcher.addEventListener(ApplicationEvent.APPLICATION_EXIT, onApplicationExit, false, 0, true);
            }
		}

        override protected function onNativeProcessIOError(event:IOErrorEvent):void
        {
            super.onNativeProcessIOError(event);
            dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_ENDED));
        }

        override protected function onNativeProcessStandardErrorData(event:ProgressEvent):void
        {
			super.onNativeProcessStandardErrorData(event);
			dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_ENDED));
		}

        override protected function onNativeProcessExit(event:NativeProcessExitEvent):void
        {
            super.onNativeProcessExit(event);

			if(isNaN(event.exitCode))
			{
				warning("Haxe build has been terminated.");
			}
			else if(event.exitCode != 0)
			{
				warning("Haxe build has been terminated with exit code: " + event.exitCode);
			}
			else
			{
				success("Haxe build has completed successfully.");
			}

			dispatcher.removeEventListener(StatusBarEvent.PROJECT_BUILD_TERMINATE, onProjectBuildTerminate);
			dispatcher.removeEventListener(ApplicationEvent.APPLICATION_EXIT, onApplicationExit);
            if(isDebugging)
            {
                dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_DEBUG_ENDED));
            }
            else
            {
                dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_ENDED));
            }
            isDebugging = false;
        }

        private function onProjectBuildTerminate(event:StatusBarEvent):void
        {
            stop();
        }

        private function onApplicationExit(event:ApplicationEvent):void
        {
            dispatcher.dispatchEvent(new StatusBarEvent(StatusBarEvent.PROJECT_BUILD_TERMINATE));
        }
	}
}