////////////////////////////////////////////////////////////////////////////////
// Copyright 2016 Prominic.NET, Inc.
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
// Author: Prominic.NET, Inc.
// No warranty of merchantability or fitness of any kind. 
// Use this software at your own risk.
////////////////////////////////////////////////////////////////////////////////
package actionScripts.plugins.ant
{
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.display.DisplayObject;
	import flash.errors.IOError;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.NativeProcessExitEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.net.FileReference;
	import flash.utils.ByteArray;
	import flash.utils.IDataInput;
	
	import mx.collections.ArrayCollection;
	import mx.controls.Alert;
	import mx.core.FlexGlobals;
	import mx.core.IFlexDisplayObject;
	import mx.events.CloseEvent;
	import mx.managers.PopUpManager;
	
	import actionScripts.events.AddTabEvent;
	import actionScripts.events.GlobalEventDispatcher;
	import actionScripts.events.NewFileEvent;
	import actionScripts.events.RefreshTreeEvent;
	import actionScripts.events.RunANTScriptEvent;
	import actionScripts.factory.FileLocation;
	import actionScripts.locator.IDEModel;
	import actionScripts.plugin.IPlugin;
	import actionScripts.plugin.PluginBase;
	import actionScripts.plugin.actionscript.as3project.vo.AS3ProjectVO;
	import actionScripts.plugin.actionscript.mxmlc.CommandLine;
	import actionScripts.plugin.settings.ISettingsProvider;
	import actionScripts.plugin.settings.event.SetSettingsEvent;
	import actionScripts.plugin.settings.vo.ISetting;
	import actionScripts.plugin.settings.vo.PathSetting;
	import actionScripts.plugins.ant.events.AntBuildEvent;
	import actionScripts.ui.IContentWindow;
	import actionScripts.ui.editor.text.TextLineModel;
	import actionScripts.ui.tabview.CloseTabEvent;
	import actionScripts.utils.HtmlFormatter;
	import actionScripts.utils.UtilsCore;
	import actionScripts.valueObjects.ConstantsCoreVO;
	import actionScripts.valueObjects.Settings;
	
	import components.popup.SelectAntFile;
	import components.popup.SelectOpenedFlexProject;
	import components.views.project.TreeView;

    public class AntBuildPlugin extends PluginBase implements IPlugin, ISettingsProvider
	{
		public static const EVENT_ANTBUILD:String = "antbuildEvent";
		public static const SELECTED_PROJECT_ANTBUILD:String = "selectedProjectAntBuild";
		
		override public function get name():String			{ return "Ant Build Setup"; }
		override public function get author():String		{ return "Moonshine Project Team"; }
		override public function get description():String	{ return "Apache® Ant Build Plugin. Esc exits."; }
		
		private var cmdFile:File;
		private var cmdLine:CommandLine;
		private var shellInfo:NativeProcessStartupInfo;
		private var nativeProcess:NativeProcess;
		private var errors:String = "";
		private var exiting:Boolean = false;
		private var _antHomePath:String;
		private var antPath:String = "ant";
		private var _instance:AntBuildPlugin;
		private var workingDir:FileLocation;
		private var file:FileLocation;
		private var selectProjectPopup:SelectOpenedFlexProject;
		private var selectAntPopup:SelectAntFile;
		private var antFiles:ArrayCollection = new ArrayCollection();
		private var currentSDK:FileLocation;
		private var _buildWithAnt:Boolean;
		private var selectedProject:AS3ProjectVO;
		private var  antBuildScreen:IFlexDisplayObject
		private var isASuccessBuild:Boolean;
		//private var antConfigureVo:AntConfigureVo;
		// test at master added
		
		public function AntBuildPlugin() 
		{
			if (Settings.os == "win")
			{
				// in windows
				antPath+=".bat";
				cmdFile = new File("c:\\Windows\\System32\\cmd.exe");
			}
			else
			{
				// in mac
				//cmdFile = new File("/Applications/Utilities/Terminal.app");
				cmdFile = new File("/bin/bash");
			}
			
			GlobalEventDispatcher.getInstance().addEventListener(RunANTScriptEvent.ANT_BUILD,runAntScriprHandler);
			GlobalEventDispatcher.getInstance().addEventListener(NewFileEvent.EVENT_ANT_BIN_URL_SET, onAntURLSet);
			GlobalEventDispatcher.getInstance().addEventListener(SELECTED_PROJECT_ANTBUILD, antBuildForSelectedProject);
		}
		
		public function get antHomePath():String
		{
			if ((_antHomePath == "" || !_antHomePath) && ConstantsCoreVO.IS_HELPER_DOWNLOADED_ANT_PRESENT) 
			{
				antHomePath = ConstantsCoreVO.IS_HELPER_DOWNLOADED_ANT_PRESENT.nativePath;
			}
			
			return _antHomePath;
		}
		public function set antHomePath(value:String):void
		{
			_antHomePath = value;
			if (_antHomePath == "")
			{
				model.antHomePath = null;
			}
			else
			{
				model.antHomePath = new FileLocation(value);
			}
		}
		
		override public function activate():void
		{
			super.activate();
			dispatcher.addEventListener(EVENT_ANTBUILD, antBuildFileHandler);
			cmdLine = new CommandLine();
			reset();
		}
		
		public function getSettingsList():Vector.<ISetting>
		{
			return Vector.<ISetting>([
				new PathSetting(this,'antHomePath', 'Ant Home', true, antHomePath)
			]);
		}
		
		override public function deactivate():void 
		{
			super.deactivate();
			nativeProcess.exit();
			reset();
			shellInfo = null;
			cmdLine = null;
		}
		
		override public function resetSettings():void
		{
			model.antScriptFile = null;
			if (ConstantsCoreVO.IS_HELPER_DOWNLOADED_ANT_PRESENT) antHomePath = ConstantsCoreVO.IS_HELPER_DOWNLOADED_ANT_PRESENT.nativePath;
			else antHomePath = "";
		}
		
		private function reset():void 
		{
			isASuccessBuild = false;
			nativeProcess = null;
			selectedProject = null;
			model.antScriptFile = null;
		}
		
		private function onAntURLSet(event:NewFileEvent):void
		{
			antHomePath = event.filePath;
		}
		
		// Call from Ant->Ant build Menu
		private function antBuildFileHandler(event:Event):void{
			_buildWithAnt = false;
			antBuildHandler();
		}
		//Call from Project explorer
		private function runAntScriprHandler(event:Event):void{
			_buildWithAnt = true;
			var tmpTreeView:TreeView = model.mainView.getTreeViewPanel();	
			selectedProject = tmpTreeView.getProjectBySelection();
			antBuildHandler();
		}
		
		protected function antBuildHandler():void 
		{
		// To check if custom sdk is set or not
			if(_buildWithAnt)
			{
				//var pvo:ProjectVO = model.activeProject;
				if(selectedProject)
				{
					 currentSDK = getCurrentSDK(selectedProject);
				}
			}
			else
			{
				currentSDK = IDEModel.getInstance().defaultSDK;
			}
			//If Flex_HOME or ANT_HOME is missing 	
		  if(!currentSDK || !model.antHomePath)
		  {
			  for each (var tab:IContentWindow in model.editors)
			  {
				  if (tab["className"] == "AntBuildScreen") 
				  {
					  model.activeEditor = tab;
					  if(currentSDK)
						  (antBuildScreen as AntBuildScreen).customSDKAvailable = true;
					 ( antBuildScreen as AntBuildScreen).refreshValue();
					 return;
				  }
			  }
			  antBuildScreen = model.flexCore.getNewAntBuild();
			  antBuildScreen.addEventListener(AntBuildEvent.ANT_BUILD,antBuildSelected);
			  if(currentSDK)
				  (antBuildScreen as AntBuildScreen).customSDKAvailable = true;
			  GlobalEventDispatcher.getInstance().dispatchEvent(
				  new AddTabEvent(antBuildScreen as IContentWindow)
			  );  
		  }
		  else
			  antBuildSelected(null);// Start Ant Process
		}
		// For projec Menu
		private function antBuildForSelectedProject(event:Event):void
		{
			_buildWithAnt = true;
		
			if (model.mainView.isProjectViewAdded)
			{
				var tmpTreeView:TreeView = model.mainView.getTreeViewPanel();	
				selectedProject = tmpTreeView.getProjectBySelection();
				//If any project from treeview is selected
				if (selectedProject)
				{
					checkForAntFile(selectedProject);
				}
				else
				{
					//Popup of project list if there is not any selected project in Project explorer
					selectProjectPopup = new SelectOpenedFlexProject();
					PopUpManager.addPopUp(selectProjectPopup, FlexGlobals.topLevelApplication as DisplayObject, false);
					PopUpManager.centerPopUp(selectProjectPopup);
					selectProjectPopup.addEventListener(SelectOpenedFlexProject.PROJECT_SELECTED, onProjectSelected);
					selectProjectPopup.addEventListener(SelectOpenedFlexProject.PROJECT_SELECTION_CANCELLED, onProjectSelectionCancelled);
				}
			}
			
			function onProjectSelected(event:Event):void
			{
				checkForAntFile(selectProjectPopup.selectedProject);
				onProjectSelectionCancelled(null);
			}
			
			function onProjectSelectionCancelled(event:Event):void
			{
				selectProjectPopup.removeEventListener(SelectOpenedFlexProject.PROJECT_SELECTED, onProjectSelected);
				selectProjectPopup.removeEventListener(SelectOpenedFlexProject.PROJECT_SELECTION_CANCELLED, onProjectSelectionCancelled);
				selectProjectPopup = null;
			}
			
			function checkForAntFile(projectReference:AS3ProjectVO):void{
				// Check if Ant file is set for project or not
				var buildFlag:Boolean = false;
				var AntFlag:Boolean = false;
				antFiles = new ArrayCollection();
				if(!projectReference.AntBuildPath)
				{
				// Find build folder within the selected folder
				//find for build.xml file with <project> tag
				for( var i:int=0;i<projectReference.projectFolder.children.length;i++){
					if(projectReference.projectFolder.children[i].name == "build")
					{
						 buildFlag = true;
						for(var j:int=0;j<projectReference.projectFolder.children[i].children.length;j++)
						{
							if(projectReference.projectFolder.children[i].children[j].file.fileBridge.extension == "xml"){
								var str:String = projectReference.projectFolder.children[i].children[j].file.fileBridge.read().toString();
								if((str.search("<project ")!=-1) || (str.search("<project>")!=-1)) {
									// Add xml files in AC.	
									AntFlag = true;
									antFiles.addItem(projectReference.projectFolder.children[i].children[j].file);
								}
							}
						}
					}
				}
				}
				else
				{
					var antFile:FileLocation = projectReference.folderLocation.resolvePath(projectReference.AntBuildPath);
					if(antFile.fileBridge.exists)
					{
						IDEModel.getInstance().antScriptFile = projectReference.folderLocation.resolvePath(projectReference.AntBuildPath);
						antBuildHandler();
						return;
					}
					else
					{
						var buildDir:FileLocation = antFile.fileBridge.parent;
						if( buildDir.fileBridge.exists)
							buildFlag = true;
						AntFlag = false;
					}
				}
				if( buildFlag)
				{
					if(!AntFlag)
					{
						Alert.yesLabel = "Choose Ant File";
						Alert.buttonWidth = 150;
						Alert.show("There is no Ant file found in the selected Project","Ant File", Alert.YES | Alert.CANCEL, null, alertListener, null, Alert.CANCEL);
						function alertListener(eventObj:CloseEvent):void {
							// Check to see if the OK button was pressed.
							if (eventObj.detail==Alert.YES) {
								model.antScriptFile = null;
								antBuildHandler();
							}
							else
							{
								return;
							}
						}
					}
					else
					{
						if(antFiles.length>1)
						{
							//Open a popup for select Ant file
							selectAntPopup = new SelectAntFile();
							PopUpManager.addPopUp(selectAntPopup, FlexGlobals.topLevelApplication as DisplayObject, false);
							PopUpManager.centerPopUp(selectAntPopup);
							selectAntPopup.antFiles = antFiles;
							selectAntPopup.addEventListener(SelectAntFile.ANTFILE_SELECTED, onAntFileSelected);
							selectAntPopup.addEventListener(SelectAntFile.ANTFILE_SELECTION_CANCELLED, onAntFileSelectionCancelled);
						}
						else
						{
							//Start Ant build if there is only one ant file
							// Set Ant file in ModelLocatior
							IDEModel.getInstance().antScriptFile = antFiles.getItemAt(0) as FileLocation;
							antBuildHandler();
						}
					}
				}
				else
				{
					// build flag flase
					{
						Alert.buttonWidth = 65;
						Alert.show("There is no Build folder in selected Project");
					}
				}
			
		}
		function onAntFileSelected(event:Event):void
		{
			//Start build which is selected from Popup
			IDEModel.getInstance().antScriptFile = selectAntPopup.selectedAntFile;
			antBuildHandler();
		}
		
		function onAntFileSelectionCancelled(event:Event):void
		{
			selectAntPopup.removeEventListener(SelectAntFile.ANTFILE_SELECTED, onAntFileSelected);
			selectAntPopup.removeEventListener(SelectAntFile.ANTFILE_SELECTION_CANCELLED, onAntFileSelectionCancelled);
			selectAntPopup = null;
		}
	  }
		
	   private function antBuildSelected(e:AntBuildEvent):void{
		   if(e)
		   {
			   if(e.selectSDK)
				   currentSDK = e.selectSDK;
			   if(e.antHome)
				   antHomePath = e.antHome.fileBridge.nativePath;
			   if(antBuildScreen)
				   GlobalEventDispatcher.getInstance().dispatchEvent(
					   new CloseTabEvent(CloseTabEvent.EVENT_CLOSE_TAB, antBuildScreen as DisplayObject)
				   );
		   }
		   if (!IDEModel.getInstance().antScriptFile)
		   {
				// Open a file chooser for select Ant script file Ant->Configue
				file = new FileLocation();
				file.fileBridge.browseForOpen("Select Build File", selectBuildFile, null, ["*.xml"]);
		  }
		  else
		  {   //If Ant file is already selected from AntScreen
				workingDir = new FileLocation(IDEModel.getInstance().antScriptFile.fileBridge.nativePath);
				startAntProcess(workingDir);
		  }
		}

		protected function selectBuildFile(fileSelected:Object):void
		{ 
			// If file is open already, just focus that editor.
			startAntProcess(new FileLocation(fileSelected.nativePath));
		}

		private function getCurrentSDK(pvo:AS3ProjectVO):FileLocation
		{
			return pvo.buildOptions.customSDK ? new FileLocation(pvo.buildOptions.customSDK.fileBridge.getFile.nativePath) : (IDEModel.getInstance().defaultSDK ? new FileLocation(IDEModel.getInstance().defaultSDK.fileBridge.getFile.nativePath) : null);
		}

		private function startAntProcess(buildDir:FileLocation):void
		{
			var processArgs:Vector.<String> = new Vector.<String>;
			var antBatPath:String = getAntBatPath();
            var sdkPath:String = UtilsCore.convertString(currentSDK.fileBridge.nativePath);
			var buildDirPath:String = buildDir.fileBridge.nativePath;

			shellInfo = new NativeProcessStartupInfo();
            shellInfo.workingDirectory = buildDir.fileBridge.parent.fileBridge.getFile as File;
			
			var isFlexJSProject:Boolean = currentSDK.resolvePath("js/bin/mxmlc").fileBridge.exists;
			var isFlexJSAfter7:Boolean = isFlexJSProject ? UtilsCore.isNewerVersionSDKThan(7, currentSDK.fileBridge.nativePath) : false;
			
			if (Settings.os == "win")
			{
				//Create file with following content:
                var antBuildRunnerPath:String = prepareAntBuildRunnerFile(buildDirPath);
				//Created file is being run
                processArgs.push("/C");
                processArgs.push("set FLEX_HOME=" + sdkPath + "&& " + antBuildRunnerPath +" -DIS_FLEXJS_AFTER_7="+ isFlexJSAfter7);

                shellInfo.arguments = processArgs;
                shellInfo.executable = cmdFile;
			}
			else 
			{
				processArgs.push("-c");
				processArgs.push("export FLEX_HOME=" + sdkPath + "&&" + antBatPath + " -file "+ UtilsCore.convertString(buildDirPath) +" -DIS_FLEXJS_AFTER_7="+ isFlexJSAfter7);
				shellInfo.arguments = processArgs;
				shellInfo.executable = cmdFile;
			}

            initShell();
		}

        private function prepareAntBuildRunnerFile(buildDirPath:String):String
        {
			var antBatPath:String = getAntBatPath();
            var buildRunnerFileName:String = "AntBuildRunner.bat";

			if (buildDirPath.indexOf(" ") > -1)
            {
                try
                {
                    var fileContent:String = antBatPath + " -f \"" + buildDirPath + "\"";
                    var antBuildRunnerFile:File = new File(File.cacheDirectory.nativePath).resolvePath(buildRunnerFileName);
                    var fileContentArray:ByteArray = new ByteArray();
                    fileContentArray.writeUTFBytes(fileContent);
                    var fileRef:FileStream = new FileStream();
                    fileRef.open(antBuildRunnerFile, FileMode.WRITE);
                    fileRef.writeBytes(fileContentArray);
                    fileRef.close();

                    return antBuildRunnerFile.nativePath;
                }
                catch (e:Error)
                {

                }
            }

			return antBatPath + " -f " + buildDirPath;
        }

		private function initShell():void 
		{
			if (nativeProcess) {
				nativeProcess.exit();
				exiting = true;
				reset();
			} else {
				startShell();
			}
		}
		
		private function startShell():void 
		{
			if (ConstantsCoreVO.IS_CONSOLE_CLEARED_ONCE) clearOutput();
			ConstantsCoreVO.IS_CONSOLE_CLEARED_ONCE = true;
			
			nativeProcess = new NativeProcess();
			nativeProcess.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, shellData);
			nativeProcess.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, shellError);
			nativeProcess.addEventListener(NativeProcessExitEvent.EXIT, shellExit);
			nativeProcess.start(shellInfo);
			print("Ant build Running");
			flush();
			
			// @for test purpose
			/*setTimeout(function():void
			{
				if (nativeProcess && nativeProcess.running)
				{
					print("Terminated");
					nativeProcess.exit(true);
					var task:TaskListManager = new TaskListManager();
					task.searchAgainstServiceName(true);
				}
			}, 4000);*/
		}
		
		private function shellData(e:ProgressEvent):void 
		{
			var output:IDataInput = nativeProcess.standardOutput;
			var data:String = output.readUTFBytes(output.bytesAvailable);
			
			var match:Array;
			
			match = data.match(/nativeProcess: Target \d not found/);
			if (match)
			{
				error("Target not found. Try again.");
				
			}
			
			match = data.match(/nativeProcess: Assigned (\d) as the compile target id/);
			if (data)
			{
				
				match = data.match(/(.*) \(\d+? bytes\)/);
				if (match) 
				{
					// Successful Build
					print("Done");
					
				}
			}
			if (data == "(nativeProcess) ") 
			{
				if (errors != "") 
				{
					compilerError(errors);
					errors = "";
				}
			}
			
			match = data.match(/BUILD SUCCESSFUL/);
			if (data)
			{
				isASuccessBuild = true;
			}
			
			if (data.charAt(data.length-1) == "\n") data = data.substr(0, data.length-1);
			
			debug("%s", data);
		}
		
		private function shellError(e:ProgressEvent):void 
		{
			var output:IDataInput = nativeProcess.standardError;
			var data:String = output.readUTFBytes(output.bytesAvailable);
			
			var syntaxMatch:Array;
			var generalMatch:Array;
			print(data);
			syntaxMatch = data.match(/(.*?)\((\d*)\): col: (\d*) Error: (.*).*/);
			if (syntaxMatch) {
				var pathStr:String = syntaxMatch[1];
				var lineNum:int = syntaxMatch[2];
				var colNum:int = syntaxMatch[3];
				var errorStr:String = syntaxMatch[4];
				pathStr = pathStr.substr(pathStr.lastIndexOf("/")+1);
				errors += HtmlFormatter.sprintf("%s<weak>:</weak>%s \t %s\n",
					pathStr, lineNum, errorStr); 
			}
			
			generalMatch = data.match(/(.*?): Error: (.*).*/);
			if (!syntaxMatch && generalMatch)
			{ 
				pathStr = generalMatch[1];
				errorStr  = generalMatch[2];
				pathStr = pathStr.substr(pathStr.lastIndexOf("/")+1);
				
				errors += HtmlFormatter.sprintf("%s: %s", pathStr, errorStr);
			}
			
			debug("%s", data);
		}
		
		private function shellExit(e:NativeProcessExitEvent):void 
		{
			debug("FSCH exit code: %s", e.exitCode);
			if (exiting) {
				exiting = false;
				startShell();
			}
			
			if (isASuccessBuild && selectedProject)
			{
				print("Files produced under DEPLOY folder.");
				// refresh the build folder
				dispatcher.dispatchEvent(new RefreshTreeEvent(selectedProject.folderLocation.resolvePath("build")));
			}
			
			reset();
			
		}
		private function flush():void 
		{
			
			
		}
		protected function compilerError(...msg):void 
		{
			var text:String = msg.join(" ");
			var textLines:Array = text.split("\n");
			var lines:Vector.<TextLineModel> = Vector.<TextLineModel>([]);
			for (var i:int = 0; i < textLines.length; i++)
			{
				if (textLines[i] == "") continue;
				text = "<error> ⚡  </error>" + textLines[i]; 
				var lineModel:TextLineModel = new TextLineModel(text);
				lines.push(lineModel);
			}
			outputMsg(lines);
		}

		private function getAntBatPath():String
		{
            var antFile:FileLocation = model.antHomePath.resolvePath(antPath);
            if (!antFile.fileBridge.exists)
            {
                antFile = model.antHomePath.resolvePath("bin/"+ antPath);
            }

            return UtilsCore.convertString(antFile.fileBridge.nativePath);
		}
	}
}
