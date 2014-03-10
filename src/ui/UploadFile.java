package ui;

import java.io.*;
import msf.*;
import javax.swing.*;
import java.util.*;

/* upload a file to the team server... */
public class UploadFile implements Runnable {
	protected FileInputStream in = null;
	protected byte[] buffer = new byte[256 * 1024];
	protected File            file = null;
	protected RpcConnection   client = null;
	protected UploadNotify    listener = null;
	protected Thread          thread = null;
	protected String          rfile = null;

	public static interface UploadNotify {
		/* call with the remote path of the file */
		public void complete(String name);
	}

	public UploadFile(RpcConnection client, File file, UploadNotify listener) {
		this.file = file;
		this.client = client;
		this.listener = listener;
		this.thread = new Thread(this);
		thread.start();
	}

	/* wait for the upload to finish and return our file */
	public String getRemoteFile() {
		if (SwingUtilities.isEventDispatchThread()) {
			System.err.println("DiSS! upload of " + file + " is happening in EDT (unsafe)");
		}

		try {
			thread.join();
		}
		catch (InterruptedException iex) {
		}

		if (rfile == null)
			throw new RuntimeException("user canceled upload of file");
		return rfile;
	}

	protected Object[] argz(byte[] data, long length) {
		/* copy relevant bytes to a temporary byte buffer */
		byte[] me = new byte[(int)length];
		for (int x = 0; x < length; x++) {
			me[x] = data[x];
		}

		Object[] args = new Object[2];
		args[0] = file.getName();
		args[1] = me;
		return args;
	}

	public void run() {
		try {
			long total = file.length();
			long start = System.currentTimeMillis();
			long read  = 0;
			long ret   = 0;
			long sofar = 0;
			double time = 0;

			ProgressMonitor progress = new ProgressMonitor(null, "Upload " + file.getName(), "Starting upload", 0, (int)total);

			in = new FileInputStream(file);

			/* read our first round and then call a function to upload the data */
			read = in.read(buffer);
			sofar += read;
			Map result = (Map)client.execute("armitage.upload", argz(buffer, read));

			while (sofar < total) {
				/* update our progress bar */
				time = (System.currentTimeMillis() - start) / 1000.0;
				progress.setProgress((int)sofar);
				progress.setNote("Speed: " + Math.round((sofar / 1024) / time) + " KB/s");

				/* honor the user's request to cancel the upload */
				if (progress.isCanceled()) {
					progress.close();
					in.close();
					return;
				}

				/* read in some data */
				read = in.read(buffer);
				sofar += read;

				/* upload the data to the team server */
				client.execute("armitage.append", argz(buffer, read));

				/* give it a break */
				Thread.yield();
			}

			/* update our progress bar */
			time = (System.currentTimeMillis() - start) / 1000.0;
			progress.setProgress((int)sofar);
			progress.setNote("Speed: " + Math.round((sofar / 1024) / time) + " KB/s");

			/* clean up, now that we're done */
			progress.close();
			in.close();

			/* call our listener, if it's not null */
			if (listener != null)
				listener.complete(result.get("file") + "");

			/* set the remote file */
			rfile = result.get("file") + "";
		}
		catch (Exception ioex) {
			JOptionPane.showMessageDialog(null, "Aborted upload of: " + file.getName() + "\n" + ioex.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
			System.err.println("Aborted upload of: " + file);
			ioex.printStackTrace();
		}
	}
}
