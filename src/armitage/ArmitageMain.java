package armitage;

import sleep.runtime.*;
import sleep.interfaces.*;
import sleep.console.*;
import sleep.bridges.*;
import sleep.error.*;
import sleep.engine.*;
import sleep.parser.ParserConfig;

import java.util.*;
import java.io.*;

import cortana.core.*;
import ui.*;

/**
 *  This class launches Armitage and loads the scripts that are part of it.
 */
public class ArmitageMain implements RuntimeWarningWatcher, Loadable, Function {
	public void processScriptWarning(ScriptWarning warning) {
		print_info(warning + "");
	}

	public static final void print_error(String message) {
		System.out.println("\u001B[01;31m[-]\u001B[0m " + message);
	}

	public static final void print_good(String message) {
		System.out.println("\u001B[01;32m[+]\u001B[0m " + message);
	}

	public static final void print_info(String message) {
		System.out.println("\u001B[01;34m[*]\u001B[0m " + message);
	}

	public static final void print_warn(String message) {
		System.out.println("\u001B[01;33m[!]\u001B[0m " + message);
	}

	public Scalar evaluate(String name, ScriptInstance script, Stack args) {
		if (name.equals("&_args")) {
			ScalarArray a = BridgeUtilities.getArray(args);
			Stack temp = new Stack();
			Iterator i = a.scalarIterator();
			while (i.hasNext()) {
				temp.add(0, i.next());
			}

			return SleepUtils.getScalar(temp);
		}
		else if (name.equals("&print_error")) {
			print_error(args.pop() + "");
		}
		else if (name.equals("&print_good")) {
			print_good(args.pop() + "");
		}
		else if (name.equals("&print_info")) {
			print_info(args.pop() + "");
		}
		else {
			try {
				String file = BridgeUtilities.getString(args, "");
				if (new File(file).exists()) {
					InputStream i = new FileInputStream(file);
					return SleepUtils.getScalar(i);
				}
				else {
					InputStream i = this.getClass().getClassLoader().getResourceAsStream(file);
					return SleepUtils.getScalar(i);
				}
			}
			catch (Exception ex) {
				throw new RuntimeException(ex.getMessage());
			}
		}
		return SleepUtils.getEmptyScalar();
	}

	protected ScriptVariables variables = new ScriptVariables();

	public void scriptLoaded(ScriptInstance script) {
		script.addWarningWatcher(this);
		script.setScriptVariables(variables);
	}

	public void scriptUnloaded(ScriptInstance script) {
	}

	protected String[] getGUIScripts() {
		return new String[] {
			"scripts/log.sl",
			"scripts/reporting.sl",
			"scripts/gui.sl",
			"scripts/util.sl",
			"scripts/targets.sl",
			"scripts/attacks.sl",
			"scripts/meterpreter.sl",
			"scripts/process.sl",
			"scripts/browser.sl",
			"scripts/pivots.sl",
			"scripts/services.sl",
			"scripts/scripts.sl",
			"scripts/loot.sl",
			"scripts/tokens.sl",
			"scripts/downloads.sl",
			"scripts/shell.sl",
			"scripts/screenshot.sl",
			"scripts/hosts.sl",
			"scripts/passhash.sl",
			"scripts/jobs.sl",
			"scripts/preferences.sl",
			"scripts/modules.sl",
			"scripts/workspaces.sl",
			"scripts/menus.sl",
			"scripts/collaborate.sl",
			"scripts/armitage.sl"
		};
	}

	protected String[] getServerScripts() {
		return new String[] {
			"scripts/util.sl",
			"scripts/preferences.sl",
			"scripts/reporting.sl",
			"scripts/server.sl"
		};
	}

	public ArmitageMain(String[] args, MultiFrame window, boolean serverMode) {
		/* tweak the parser to recognize a few useful escapes */
		ParserConfig.installEscapeConstant('c', console.Colors.color + "");
		ParserConfig.installEscapeConstant('U', console.Colors.underline + "");
		ParserConfig.installEscapeConstant('o', console.Colors.cancel + "");

		/* setup a function or two */
		Hashtable environment = new Hashtable();
		environment.put("&resource", this);
		environment.put("&_args", this);
		environment.put("&print_error", this);
		environment.put("&print_good", this);
		environment.put("&print_info", this);

		/* set our command line arguments into a var */
		variables.putScalar("@ARGV", ObjectUtilities.BuildScalar(false, args));

		ScriptLoader loader = new ScriptLoader();
		loader.addSpecificBridge(this);

		/* setup Cortana event and filter bridges... we will install these into
		   Armitage */
		if (!serverMode) {
			EventManager events   = new EventManager();
			FilterManager filters = new FilterManager();

			variables.putScalar("$__events__", SleepUtils.getScalar(events));
			variables.putScalar("$__filters__", SleepUtils.getScalar(filters));
			variables.putScalar("$__frame__", SleepUtils.getScalar(window));

			loader.addGlobalBridge(events.getBridge());
			loader.addGlobalBridge(filters.getBridge());
		}

		/* load the appropriate scripts */
		String[] scripts = serverMode ? getServerScripts() : getGUIScripts();
		int x = -1;
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
		/* check for server mode option */
		boolean serverMode = false;

		int x = 0;
		for (x = 0; x < args.length; x++) {
			if (args[x].equals("--server"))
				serverMode = true;
		}

		/* setup our armitage instance */
		if (serverMode) {
			new ArmitageMain(args, null, serverMode);
		}
		else {
			MultiFrame.setupLookAndFeel();
			MultiFrame frame = new MultiFrame();
			new ArmitageMain(args, frame, serverMode);
		}
	}
}
