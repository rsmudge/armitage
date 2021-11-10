package msf;

import java.io.*;

public interface Async {
	public void execute_async(String methodName);
	public void execute_async(String methodName, Object[] args);
	public void execute_async(String methodName, Object[] args, RpcCallback callback);
	public boolean isConnected();
	public void disconnect();
	public boolean isResponsive();
}
