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
package actionScripts.plugin.java.javaproject
{
    import actionScripts.plugin.PluginBase;
    import actionScripts.plugin.project.ProjectType;
    import actionScripts.events.NewProjectEvent;
    import actionScripts.plugin.project.ProjectTemplateType;
    import actionScripts.plugin.settings.SettingsView;
    import actionScripts.plugin.java.javaproject.vo.JavaProjectVO;
	
	public class JavaProjectPlugin extends PluginBase
	{	
		public var activeType:uint = ProjectType.JAVA;
		
		override public function get name():String 			{ return "Java Project Plugin"; }
		override public function get author():String 		{ return "Moonshine Project Team"; }
		override public function get description():String 	{ return "Java project importing, exporting & scaffolding."; }
		
		override public function activate():void
		{
			dispatcher.addEventListener(NewProjectEvent.CREATE_NEW_PROJECT, createNewProjectHandler);
			
			super.activate();
		}
		
		override public function deactivate():void
		{
			dispatcher.removeEventListener(NewProjectEvent.CREATE_NEW_PROJECT, createNewProjectHandler);
			
			super.deactivate();
		}
		
		private function createNewProjectHandler(event:NewProjectEvent):void
		{
			if(!canCreateProject(event))
			{
				return;
			}
			
			model.javaCore.createProject(event);
		}

        private function canCreateProject(event:NewProjectEvent):Boolean
        {
            var projectTemplateName:String = event.templateDir.fileBridge.name;
            return projectTemplateName.indexOf(ProjectTemplateType.JAVA) != -1;
        }
	}
}