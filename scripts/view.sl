import console.*;
import armitage.*;

menu("View", 'V');

item("View", "New Console", 'C', {
	local('$console $result $thread');
	$console = [new Console];
	$result = call($client, "console.create");
	$thread = [new ConsoleClient: $console, $client, "console.read", "console.write", "console.destroy", $result['id'], $null];
	[$thread setMetasploitConsole];

	[$console addWordClickListener: lambda({
		local('$word');
		$word = [$1 getActionCommand];

		if ($word in @exploits || $word in @auxiliary) {
			[$thread sendString: "use $word $+ \n"];
		}
		else if ($word in @payloads) {
			[$thread sendString: "set PAYLOAD $word $+ \n"];
		}
	}, \$thread)];

	[$frame addTab: "Console " . $result['id'], $console, $thread];
});

item("View", "Targets", 'T', {
	createTargetTab();
});
