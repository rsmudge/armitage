package armitage;

import console.Console;
import msf.*;
import java.util.*;
import java.awt.*;
import java.awt.event.*;
import javax.swing.*;

/* A generic class to manage reading/writing to a console. Keeps the code simpler (although the Sleep code to do this is 
   simpler than this Java code. *sigh* */
public class CommandClient implements Runnable {
	protected RpcConnection connection;
	protected String        readCommand;
	protected String        writeCommand;
	protected String        session;
	protected String        command[];
	protected static final Object lock = new Integer(100);
	protected CommandCallback callback;
	protected boolean       asynchronous;

	public CommandClient(RpcConnection connection, String command, String readCommand, String writeCommand, String session, CommandCallback callback, boolean async) {
		this(connection, new String[] { command }, readCommand, writeCommand, session, callback, async);
	}

	public CommandClient(RpcConnection connection, String command[], String readCommand, String writeCommand, String session, CommandCallback callback, boolean async) {
		this.command = command;
		this.connection = connection;
		this.readCommand = readCommand;
		this.writeCommand = writeCommand;
		this.session = session;
		this.callback = callback;
		this.asynchronous = async;
		new Thread(this).start();
	}

	public void run() {
		if (!asynchronous) {
			synchronized (lock) {
				for (int x = 0; x < command.length; x++)
					exec(x);
			}
		}
		else {
			for (int x = 0; x < command.length; x++) 
				exec(x);
		}
	}

	public boolean isEmptyData(String data) {
		return "".equals(data) || "null".equals(data);
	}

	public void exec(int x) {
		Map read;
		StringBuffer output = new StringBuffer();

		try {
			connection.execute(writeCommand, new Object[] { session, Base64.encode(command[x]) });

			int count = 0;

			Thread.sleep(500);

			while ((read = (Map)(connection.execute(readCommand, new Object[] { session }))) != null) {
				String text = null;
				if (! isEmptyData( read.get("data") + "" )  ) {
					text = new String(Base64.decode( read.get("data") + "" ), "UTF-8");
					output.append(text);
				}
				else if ("false".equals( read.get("busy") + "" ) && isEmptyData( read.get("data") + "" )) {
					/* this is a bug that annoys the hell out of me. Sometimes an
					   executed command is swallowed by metasploit. This is an attempt
					   to work around that by retrying the command once if nothing was
					   read in response to it. */

					if (count > 0) {
						break;
					}
					else {
						connection.execute(writeCommand, new Object[] { session, Base64.encode(command[x]) });
					}
				}
				else if ("failure".equals( read.get("result") + "" )) {
					break;
				}

				Thread.sleep(500);
				count++;
			}

			if (callback != null)
				callback.callback(command[x], session, output.toString());
		}
		catch (Exception javaSucksBecauseItMakesMeCatchEverythingFuckingThing) {
			javaSucksBecauseItMakesMeCatchEverythingFuckingThing.printStackTrace();
		}
	}
}
