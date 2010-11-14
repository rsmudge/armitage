package armitage;

import sleep.runtime.*;
import sleep.interfaces.*;
import sleep.console.*;
import sleep.bridges.*;
import sleep.error.*;

import java.util.*;

import java.io.*;

/**
 *  This class launches Armitage and loads the scripts that are part of it.
 */
public class ArmitageMain implements RuntimeWarningWatcher, Loadable, Function {   
	public void processScriptWarning(ScriptWarning warning) {
		System.out.println(warning);
	}

	public Scalar evaluate(String name, ScriptInstance script, Stack args) {
		try {
			InputStream i = this.getClass().getClassLoader().getResourceAsStream(BridgeUtilities.getString(args, ""));
			return SleepUtils.getScalar(i);
		}
		catch (Exception ex) {
			throw new RuntimeException(ex.getMessage());
		}
	}

	protected ScriptVariables variables = new ScriptVariables();

	public void scriptLoaded(ScriptInstance script) {
		script.addWarningWatcher(this);
		script.setScriptVariables(variables);
	}

	public void scriptUnloaded(ScriptInstance script) {
	}

	public ArmitageMain() {
		Hashtable environment = new Hashtable();
		environment.put("&resource", this);

		ScriptLoader loader = new ScriptLoader();
		loader.addSpecificBridge(this);

		String[] scripts = new String[] {
			"scripts/gui.sl",
			"scripts/util.sl",
			"scripts/targets.sl",
			"scripts/attacks.sl",
			"scripts/meterpreter.sl",
			"scripts/process.sl",
			"scripts/keyscan.sl",
			"scripts/browser.sl",
			"scripts/pivots.sl",
			"scripts/services.sl",
			"scripts/shell.sl",
			"scripts/screenshot.sl",
			"scripts/hosts.sl",
			"scripts/passhash.sl",
			"scripts/jobs.sl",
			"scripts/preferences.sl",
			"scripts/modules.sl",
			"scripts/menus.sl",
			"scripts/armitage.sl"
		};

		int x = 0;

		try {
			for (x = 0; x < scripts.length; x++) {
				InputStream i = this.getClass().getClassLoader().getResourceAsStream(scripts[x]);
				ScriptInstance si = loader.loadScript(scripts[x], i, environment);
				si.runScript();
			}
		}
		catch (YourCodeSucksException yex) {
			System.out.println("*** File: " + scripts[x]);
			yex.printErrors(System.out);
		}
		catch (IOException ex) {
			System.err.println(ex);
			ex.printStackTrace();
		}
	}

	public static void main(String args[]) {
		new ArmitageMain();
	}
}
