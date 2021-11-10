package ui;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import java.util.*;

import java.io.*;

/* Spawn common dialogs in their own thread (so they don't block Sleep interpreter)
   and report their results to a callback function */
public class SafeDialogs {
	/* our callback interface... will always return a string I guess */
	public interface SafeDialogCallback {
		public void result(String r);
	}

	/* prompts the user with a yes/no question. Does not call callback unless the user presses
	   yes. askYesNo is always a confirm action anyways */
	public static void askYesNo(final String text, final String title, final SafeDialogCallback callback) {
		new Thread(new Runnable() {
			public void run() {
				int result = JOptionPane.showConfirmDialog(null, text, title, JOptionPane.YES_NO_OPTION);
				if (result == JOptionPane.YES_OPTION || result == JOptionPane.OK_OPTION) {
					callback.result("yes");
				}
			}
		}).start();
	}

	public static void ask(final String text, final String initial, final SafeDialogCallback callback) {
		new Thread(new Runnable() {
			public void run() {
				String result = JOptionPane.showInputDialog(text, initial);
				callback.result(result);
			}
		}).start();
	}

	/* prompt the user with a saveFile dialog */
	public static void saveFile(final JFrame frame, final String selection, final SafeDialogCallback callback) {
		new Thread(new Runnable() {
			public void run() {
				JFileChooser fc = new JFileChooser();

				if (selection != null) {
					fc.setSelectedFile(new File(selection));
				}

				if (fc.showSaveDialog(frame) == 0) {
					File file = fc.getSelectedFile();
					if (file != null) {
						callback.result(file + "");
						return;
					}
				}
			}
		}).start();
	}

	public static void openFile(final String title, final String sel, final String dir, final boolean multi, final boolean dirsonly, final SafeDialogCallback callback) {
		new Thread(new Runnable() {
			public void run() {
				JFileChooser fc = new JFileChooser();

				if (title != null)
					fc.setDialogTitle(title);

				if (sel != null)
					fc.setSelectedFile(new File(sel));

				if (dir != null)
					fc.setCurrentDirectory(new File(dir));

				fc.setMultiSelectionEnabled(multi);

				if (dirsonly)
					fc.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);

				if (fc.showOpenDialog(null) != JFileChooser.APPROVE_OPTION)
					return;

				if (multi) {
					StringBuffer buffer = new StringBuffer();
					File[] r = fc.getSelectedFiles();

					for (int x = 0; x < r.length; x++) {
						/* probably always true, but a little defensive coding
						   never hurt anyone */
						if (r[x] != null && r[x].exists()) {
							buffer.append(r[x]);
							if ((x + 1) < r.length)
								buffer.append(",");
						}
					}
					callback.result(buffer.toString());
				}
				else {
					if (fc.getSelectedFile() != null && fc.getSelectedFile().exists())
						callback.result(fc.getSelectedFile() + "");
				}
			}
		}).start();
	}
}
