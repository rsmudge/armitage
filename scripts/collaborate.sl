#
# Armitage Collaboration Feature... make no mistake, I'm extremely excited about this.
#

import msf.*;
import armitage.*;
import console.*;

sub createEventLogTab {
        local('$client $console');

	$client = [new ConsoleClient: $null, $mclient, "armitage.poll", "armitage.push", $null, "", $null];
        $console = [new Console: $preferences];
        [$client setWindow: $console];
	[$client setEcho: $null];
	[$console updatePrompt: "> "];
        [$frame addTab: "Event Log", $console, $null];
}

sub c_client {
	# run this thing in its own thread to avoid really stupid deadlock situations
	return wait(fork({
		local('$handle $client');
		$handle = connect($host, $port);
		$client = newInstance(^RpcConnection, lambda({
			writeObject($handle, @_);
			return readObject($handle);
		}, \$handle));
		return $client;
	}, $host => $1, $port => $2));
}

sub checkForCollaborationServer {
	cmd($client, $console, "set ARMITAGE_SERVER", {
		if ($3 ismatch "ARMITAGE_SERVER => (.*?):(.*?)/(.*?)\n") {
			local('$host $port $token');
			($host, $port, $token) = matched();
			setup_collaboration($host, $port, $token);
		}
	});
}


sub setup_collaboration {
	local('$host $port $ex');
	
	try {
		$mclient = c_client($1, $2);	
		call($mclient, "armitage.validate", $3, ask("What is your nickname?"));
		showError("Collaboration Setup!");
		recreate_view_items();
	}
	catch $ex {
		showError("Collaboration Connection Failed. :(\n" . [$ex getMessage]);
	}
}
