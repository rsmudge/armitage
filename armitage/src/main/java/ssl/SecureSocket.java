package ssl;

import java.net.*;
import java.io.*;
import javax.net.ssl.*;
import javax.net.*;

import java.security.*;
import java.security.cert.*;

import sleep.bridges.io.*;

/* taken from jIRCii, I developed it, so I get to do what I want ;) */
public class SecureSocket {
	protected SSLSocket socket;

	public SecureSocket(String host, int port, ArmitageTrustListener checker) throws Exception {
		socket = null;

		SSLContext sslcontext = SSLContext.getInstance("SSL");
		sslcontext.init(null, new TrustManager[] { new ArmitageTrustManager(checker) }, new java.security.SecureRandom());
		SSLSocketFactory factory = (SSLSocketFactory) sslcontext.getSocketFactory();

		socket = (SSLSocket)factory.createSocket(host, port);

		socket.setSoTimeout(4048);
		socket.startHandshake();
	}

	public void authenticate(String password) {
		try {
			/* we're past the handshake, so let's allow reads time to happen */
			socket.setSoTimeout(0);

			DataInputStream datain   = new DataInputStream(socket.getInputStream());
			DataOutputStream dataout = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream()));

			/* write our magic header */
			dataout.writeInt(0xBEEF);

			/* write our password's length */
			dataout.writeByte(password.length());

			/* write our password out */
			for (int x = 0; x < password.length(); x++)
				dataout.writeByte((byte)password.charAt(x));

			/* pad the password please */
			for (int x = password.length(); x < 256; x++)
				dataout.writeByte('A');

			/* flush! */
			dataout.flush();

			/* read in a byte to indicate status */
			int result = datain.readInt();

			if (result == 0xCAFE)
				return;
			else
				throw new RuntimeException("authentication failure!");
		}
		catch (RuntimeException rex) {
			throw rex;
		}
		catch (Exception ex) {
			ex.printStackTrace();
			throw new RuntimeException(ex);
		}
	}

	public IOObject client() {
		try {
			IOObject temp = new IOObject();
			temp.openRead(socket.getInputStream());
			temp.openWrite(new BufferedOutputStream(socket.getOutputStream(), 8192 * 8));
			socket.setSoTimeout(0);
			return temp;
		}
		catch (Exception ex) {
			throw new RuntimeException(ex);
		}
	}

	public Socket getSocket() {
		return socket;
	}
}

