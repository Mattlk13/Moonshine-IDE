package build;

// Usage:
// $: haxe --run build/InstallDependencies.hx --target=windows --haxelibpath=C:/MoonshineSDKs/Haxe/lib
class InstallDependencies {
	public static function main() {
		var namedArgs = parseNamedArguments(Sys.args());

		trace('Installing dependencies...');
		trace('target: ${namedArgs["target"]}');
		trace('haxelibpath: ${namedArgs["haxelibpath"]}');
		installDependencies(namedArgs['target'], namedArgs['haxelibpath']);
	}

	static function parseNamedArguments(args:Array<String>):Map<String, String> {
		var result = new Map<String, String>();

		for (arg in args) {
			if (StringTools.startsWith(arg, "--")) {
				var parts = arg.split('=');
				var key = parts[0].substr(2); // Remove the "--" prefix
				var value = parts.length > 1 ? parts[1] : "";
				result.set(key, value);
			}
		}

		return result;
	}

	public static function installDependencies(target:String, haxelibPath:String) {
		Sys.command('haxelib --global update haxelib --quiet --never');

		Sys.println('[InstallDependencies] Starts installing..');
		// Install Lime and dependencies
		Sys.println('[InstallDependencies] Installing hxcpp - stable');
		Sys.command('haxelib install hxp --quiet');
		Sys.println('[InstallDependencies] Installing format - stable');
		Sys.command('haxelib install format --quiet');

		// Desktop builds use stable Lime
		Sys.println('[InstallDependencies] Installing lime - stable');
		Sys.command('haxelib install lime --quiet');

		// Install and setup openfl
		Sys.println('[InstallDependencies] Installing openfl - stable');
		Sys.command('haxelib install openfl --quiet --never');
		Sys.println('[InstallDependencies] Running openfl setup');
		Sys.command('yes y | haxelib run openfl setup --quiet --never');

		// Install hxcpp AFTER openfl setup.
		// Why here (not earlier): `haxelib run openfl setup` auto-upgrades hxcpp
		// ("hxcpp was updated" in its output), which clobbers any earlier install
		// and leaves a non-git version as current. We pin a Github version
		// (it contains a Windows socket-connection fix not in the released hxcpp,
		// and Lime's ndlls were built against 4.3.45 so this version aligns ABI),
		// so we install it last so it stays current.
		// Why compile hxcpp.n: the git install ships no hxcpp.n, and newer
		// lime/openfl reject the version otherwise. Haxe's eval Sys.command(String)
		// does not go through a shell, so shell operators (&&, cd) are unreliable —
		// use haxe's --cwd flag with the argv form of Sys.command instead.
		Sys.println('[InstallDependencies] Installing hxcpp - git 4.3.45');
		Sys.command('haxelib git hxcpp https://github.com/HaxeFoundation/hxcpp.git v4.3.45 --quiet');
		// Normalize so this works whether haxelibPath has a trailing slash or not
		// (macOS returns one from `haxelib config`, Linux/Windows do not).
		var hxcppGitDir = haxe.io.Path.normalize('$haxelibPath/hxcpp/git');
		var hxcppToolsDir = '$hxcppGitDir/tools/hxcpp';
		var hxcppNPath = '$hxcppGitDir/hxcpp.n';

		// Diagnostic: verify what `haxelib git` actually checked out.
		// If the requested ref (e.g. v4.3.140) is a tag rather than a branch and
		// haxelib silently falls back to the default branch, the haxelib.json
		// version field exposes the mismatch.
		Sys.println('[InstallDependencies] Verifying hxcpp checkout at $hxcppGitDir:');
		Sys.print('[InstallDependencies]   HEAD: ');
		Sys.command('git', ['-C', hxcppGitDir, 'rev-parse', 'HEAD']);
		Sys.print('[InstallDependencies]   describe: ');
		Sys.command('git', ['-C', hxcppGitDir, 'describe', '--tags', '--always']);
		Sys.print('[InstallDependencies]   branch: ');
		Sys.command('git', ['-C', hxcppGitDir, 'rev-parse', '--abbrev-ref', 'HEAD']);
		try {
			var json:Dynamic = haxe.Json.parse(sys.io.File.getContent('$hxcppGitDir/haxelib.json'));
			Sys.println('[InstallDependencies]   haxelib.json version field: ${json.version}');
		} catch (e) {
			Sys.println('[InstallDependencies]   ERROR reading haxelib.json: $e');
		}
		// Definitive: ask haxelib itself which directory it will resolve hxcpp to.
		// If `git` is the active version, this path ends in `/hxcpp/git/`; if a
		// stable like 4.3.2 is silently active, it ends in `/hxcpp/4,3,2/`.
		Sys.print('[InstallDependencies]   haxelib path hxcpp -> ');
		Sys.command('haxelib', ['path', 'hxcpp']);
		Sys.print('[InstallDependencies]   haxelib libpath hxcpp -> ');
		Sys.command('haxelib', ['libpath', 'hxcpp']);

		Sys.println('[InstallDependencies] Compiling hxcpp.n via: haxe --cwd "$hxcppToolsDir" compile.hxml');
		var compileExitCode = Sys.command('haxe', ['--cwd', hxcppToolsDir, 'compile.hxml']);
		if (compileExitCode != 0) {
			Sys.println('[InstallDependencies] ERROR: haxe compile.hxml failed (exit code $compileExitCode)');
			Sys.exit(1);
		}
		if (!sys.FileSystem.exists(hxcppNPath)) {
			Sys.println('[InstallDependencies] ERROR: expected $hxcppNPath after compile, but file is missing');
			Sys.exit(1);
		}
		Sys.println('[InstallDependencies] hxcpp.n compiled successfully');

		Sys.println('[InstallDependencies] Installed haxelibs - After hxcpp install:');
		Sys.command('haxelib list');

		// Install other dependencies
		Sys.println('[InstallDependencies] Installing other dependencies - mixed');
		Sys.command('haxelib install hxp --quiet --never');
		Sys.command('haxelib install format --quiet --never');
		Sys.command('haxelib install actuate --quiet --never');
		Sys.command('haxelib install amfio --quiet --never');
		Sys.command('haxelib git feathersui https://github.com/feathersui/feathersui-openfl.git --quiet --never');
		Sys.command('haxelib git moonshine-openfl-language-client https://github.com/Moonshine-IDE/moonshine-openfl-language-client.git --quiet --never');
		Sys.command('haxelib git moonshine-openfl-debug-adapter-client https://github.com/Moonshine-IDE/moonshine-openfl-debug-adapter-client.git --quiet --never');
		Sys.command('haxelib install markdown-openfl-textfield --quiet');
		Sys.command('haxelib git moonshine-feathersui-text-editor https://github.com/Moonshine-IDE/moonshine-feathersui-text-editor.git --quiet --never');
		Sys.command('haxelib fixrepo');

		// Print installed haxelibs
		Sys.print('\n\nInstalled haxelibs:\n');
		Sys.command('haxelib list');
	}
}