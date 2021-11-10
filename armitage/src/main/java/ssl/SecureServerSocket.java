package ssl;

import java.net.*;
import java.io.*;
import javax.net.ssl.*;
import javax.net.*;

import java.security.*;
import java.security.cert.*;

import sleep.bridges.io.*;

/* internal package... I don't like it, but need it to generate a self-signed cert */
import sun.security.x509.*;

import java.math.*;
import java.util.*;

import armitage.*;

/* taken from jIRCii, I developed it, so I get to do what I want ;) */
public class SecureServerSocket {
	protected ServerSocket server;
	protected String last = "";

	public String last() {
		return last;
	}

	public IOObject accept() {
		try {
			Socket client = server.accept();
			//client.setTcpNoDelay(true);
			IOObject temp = new IOObject();
			temp.openRead(client.getInputStream());
			temp.openWrite(new BufferedOutputStream(client.getOutputStream(), 8192 * 8));
			last = client.getInetAddress().getHostAddress();
			client.setSoTimeout(0);
			return temp;
		}
		catch (Exception ex) {
			throw new RuntimeException(ex);
		}
	}

	protected boolean authenticate(Socket client, String pass, String host) throws IOException {
		DataInputStream authin   = new DataInputStream(client.getInputStream());
		DataOutputStream authout = new DataOutputStream(client.getOutputStream());

		/* read in magic header */
		int magic = authin.readInt();
		if (magic != 0xBEEF) {
			ArmitageMain.print_error("rejected client from " + host + ": invalid auth protocol (old client?)");
			return false;
		}

		/* read in the length of the team server password */
		int length = authin.readUnsignedByte();
		if (length <= 0) {
			ArmitageMain.print_error("rejected client from " + host + ": bad password length");
			return false;
		}

		/* read in the actual password */
		StringBuffer mypass = new StringBuffer();
		for (int x = 0; x < length; x++) {
			mypass.append((char)authin.readUnsignedByte());
		}

		/* read in the padding please */
		for (int x = length; x < 256; x++)
			authin.readUnsignedByte();

		/* check if the password matches */
		if (mypass.toString().equals(pass)) {
			authout.writeInt(0xCAFE); /* we're good! */
			return true;
		}
		else {
			authout.writeInt(0x0); /* auth failure */
			ArmitageMain.print_error("rejected client from " + host + ": invalid password");
			return false;
		}
	}

	public IOObject acceptAuthenticated(String pass) {
		try {
			Socket client = server.accept();

			if ( authenticate( client, pass, client.getInetAddress().getHostAddress()) ) {
				IOObject temp = new IOObject();
				temp.openRead(client.getInputStream());
				temp.openWrite(new BufferedOutputStream(client.getOutputStream(), 8192 * 8));
				last = client.getInetAddress().getHostAddress();
				client.setSoTimeout(0);

				return temp;
			}
			else {
				try {
					client.close();
				}
				catch (Exception ex) {
				}
				return null;
			}
		}
		catch (Exception ex) {
			ex.printStackTrace();
			throw new RuntimeException(ex);
		}
	}

	public SecureServerSocket(int port) throws Exception {
		ServerSocketFactory factory = getFactory();
		server = factory.createServerSocket(port, 32);
		server.setSoTimeout(0); /* we wait forever until something comes */
		server.setReuseAddress(true);
	}

	private ServerSocketFactory getFactory() throws Exception {
		return SSLServerSocketFactory.getDefault();
	}

	public ServerSocket getServerSocket() {
		return server;
	}

	/* grab the SSL cert we're using and digest it with SHA-1. Return this so we may
	   present it on server startup */
	public String fingerprint() {
		try {
			FileInputStream is = new FileInputStream(System.getProperty("javax.net.ssl.keyStore"));
			KeyStore keystore = KeyStore.getInstance(KeyStore.getDefaultType());
			keystore.load(is, (System.getProperty("javax.net.ssl.keyStorePassword") + "").toCharArray());

			Enumeration en = keystore.aliases();
			if (en.hasMoreElements()) {
				String alias = en.nextElement() + "";
				java.security.cert.Certificate cert = keystore.getCertificate(alias);

				byte[] bytesOfMessage = cert.getEncoded();
				MessageDigest md = MessageDigest.getInstance("SHA1");
				byte[] thedigest = md.digest(bytesOfMessage);

				BigInteger bi = new BigInteger(1, thedigest);
				return bi.toString(16);
			}
		}
		catch (Exception ex) {
			System.err.println(ex);
			ex.printStackTrace();
		}
		return "unknown";
	}
}

