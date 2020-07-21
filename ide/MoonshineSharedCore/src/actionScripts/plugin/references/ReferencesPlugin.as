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
package actionScripts.plugin.references
{
	import actionScripts.plugin.projectPanel.events.ProjectPanelPluginEvent;

	import flash.events.Event;
	
	import feathers.data.ArrayCollection;
	
	import actionScripts.events.LanguageServerEvent;
	import actionScripts.events.ReferencesEvent;
	import actionScripts.plugin.PluginBase;
	import moonshine.plugin.references.view.ReferencesView;
	import actionScripts.ui.editor.LanguageServerTextEditor;
	import actionScripts.valueObjects.ConstantsCoreVO;
	import actionScripts.valueObjects.Location;
	import actionScripts.ui.FeathersUIWrapper;
	import actionScripts.ui.FeathersUIWrapper;
	import mx.controls.Alert;
	import actionScripts.events.OpenLocationEvent;

	public class ReferencesPlugin extends PluginBase
	{
		public static const EVENT_OPEN_FIND_REFERENCES_VIEW:String = "openFindReferencesView";
		
		public function ReferencesPlugin()
		{
			referencesView = new ReferencesView();
			referencesViewWrapper = new FeathersUIWrapperWithTitle(this.referencesView);
			referencesViewWrapper.percentWidth = 100;
			referencesViewWrapper.percentHeight = 100;
		}

		override public function get name():String { return "References Plugin"; }
		override public function get author():String { return ConstantsCoreVO.MOONSHINE_IDE_LABEL +" Project Team"; }
		override public function get description():String { return "Displays all references for a symbol in the entire workspace."; }

		private var referencesViewWrapper:FeathersUIWrapperWithTitle;
		private var referencesView:ReferencesView;
		private var isReferencesViewVisible:Boolean;

		override public function activate():void
		{
			super.activate();
			referencesView.addEventListener(ReferencesView.EVENT_OPEN_SELECTED_REFERENCE, handleOpenSelectedReference);
			dispatcher.addEventListener(EVENT_OPEN_FIND_REFERENCES_VIEW, handleOpenFindReferencesView);
			dispatcher.addEventListener(ReferencesEvent.EVENT_SHOW_REFERENCES, handleShowReferences);
		}

		override public function deactivate():void
		{
			super.deactivate();
			referencesView.removeEventListener(ReferencesView.EVENT_OPEN_SELECTED_REFERENCE, handleOpenSelectedReference);
			dispatcher.removeEventListener(EVENT_OPEN_FIND_REFERENCES_VIEW, handleOpenFindReferencesView);
			dispatcher.removeEventListener(ReferencesEvent.EVENT_SHOW_REFERENCES, handleShowReferences);
		}

		private function handleOpenFindReferencesView(event:Event):void
		{
			var editor:LanguageServerTextEditor = model.activeEditor as LanguageServerTextEditor;
			if(!editor)
			{
				return;
			}

			var startLine:int = editor.editor.model.selectedLineIndex;
			var startChar:int = editor.editor.startPos;
			var endLine:int = editor.editor.model.selectedLineIndex;
			var endChar:int = editor.editor.model.caretIndex;
			dispatcher.dispatchEvent(new LanguageServerEvent(LanguageServerEvent.EVENT_FIND_REFERENCES,
				editor.currentFile.fileBridge.url, startChar, startLine, endChar, endLine));
		}

		private function handleShowReferences(event:ReferencesEvent):void
		{
			var collection:ArrayCollection = referencesView.references;
			collection.removeAll();
			var references:Vector.<Location> = event.locations;
			var itemCount:int = references.length;
			for(var i:int = 0; i < itemCount; i++)
			{
				var symbol:Location = references[i];
				collection.add(symbol);
			}
			collection.filterFunction = null;
			collection.refresh();

			if (!isReferencesViewVisible)
			{
				dispatcher.dispatchEvent(new ProjectPanelPluginEvent(ProjectPanelPluginEvent.ADD_VIEW_TO_PROJECT_PANEL, referencesViewWrapper));
				isReferencesViewVisible = true;

				referencesView.addEventListener(Event.REMOVED_FROM_STAGE, onReferenceViewRemovedFromStage);
			}
		}

		private function handleOpenSelectedReference(event:Event):void {
			var selectedReference:Location = this.referencesView.selectedReference;
			if(!selectedReference)
			{
				Alert.show("Please select an item to open.");
				return;
			}

			dispatcher.dispatchEvent(
				new OpenLocationEvent(OpenLocationEvent.OPEN_LOCATION, selectedReference));
		}

		private function onReferenceViewRemovedFromStage(event:Event):void
		{
			referencesView.references.removeAll();
			isReferencesViewVisible = false;
			referencesView.removeEventListener(Event.REMOVED_FROM_STAGE, onReferenceViewRemovedFromStage);
		}
	}
}

import actionScripts.interfaces.IViewWithTitle;
import actionScripts.ui.FeathersUIWrapper;
import feathers.core.FeathersControl;

class FeathersUIWrapperWithTitle extends FeathersUIWrapper implements IViewWithTitle {
	public function FeathersUIWrapperWithTitle(feathersUIControl:FeathersControl)
	{
		super(feathersUIControl);
	}

	public function get title():String {
		var feathersUIControlWithTitle:IViewWithTitle = this.feathersUIControl as IViewWithTitle;
		if(!feathersUIControlWithTitle)
		{
			return "";
		}
		return feathersUIControlWithTitle.title;
	}
}