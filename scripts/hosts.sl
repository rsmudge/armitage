import msf.*;

import javax.swing.*;
import javax.swing.event.*;

import java.awt.*;
import java.awt.event.*;

sub addHostDialog {
	local('$dialog $label $text $finish $button');
	$dialog = [new JDialog: $frame, "Add Hosts", 0];
	[$dialog setSize: 320, 240];
	[$dialog setLayout: [new BorderLayout]];
	[$dialog setLocationRelativeTo: $frame];

	$label = [new JLabel: "Enter one host/line:"];
	$text = [new JTextArea];

	$finish = [new JPanel];
	[$finish setLayout: [new FlowLayout: [FlowLayout CENTER]]];

	$button = [new JButton: "Add"];
	[$finish add: $button];

	[$button addActionListener: lambda({
		local('@hosts');
		@hosts = split("[\n\s]", [$text getText]);
		cmd_safe("hosts -a " . join(" ", @hosts), lambda({
			showError("Added $x host" . iff($x != 1, "s"));
			elog("added $x host" . iff($x != 1, "s"));
		}, $x => size(@hosts)));
		[$dialog setVisible: 0];
	}, \$text, \$dialog)];

	[$dialog add: $label, [BorderLayout NORTH]];
	[$dialog add: [new JScrollPane: $text], [BorderLayout CENTER]];
	[$dialog add: $finish, [BorderLayout SOUTH]];

	[$dialog setVisible: 1];
}

sub host_items {
	local('$i $j $k');
	item($1, "Import Hosts", 'I', &importHosts);

	$j = menu($1, "Nmap Scan", 'S');
		item($j, "Intense Scan", $null, createNmapFunction("-T5 -A -v"));
		item($j, "Intense Scan + UDP", $null, createNmapFunction("-sS -sU -T5 -A -v"));
		item($j, "Intense Scan, all TCP ports", $null, createNmapFunction("-p 1-65535 -T5 -A -v"));
		item($j, "Intense Scan, no ping", $null, createNmapFunction("-T5 -A -v -Pn"));
		item($j, "Ping Scan", $null, createNmapFunction("-T5 -sn"));
		item($j, "Quick Scan", $null, createNmapFunction("-T5 -F"));
		item($j, "Quick Scan (OS detect)", $null, createNmapFunction("-sV -T5 -O -F --version-light"));
		item($j, "Comprehensive", $null, createNmapFunction("-sS -sU -T5 -A -v -PE -PP -PS80,443 -PA3389 -PU40125 -PY -g 53"));

	item($1, "Add Hosts...", 'A', &addHostDialog);

	separator($1);

	item($1, "Clear Database", 'C', &clearDatabase);
}

# oh yay, Metasploit now normalizes OS info (so I don't have to). Except the new constants
# they use are different than the ones they have used... *sigh* time to future proof my code.
sub normalize {
	if ("*Windows*" iswm $1) {
		return "Windows";
	}
	else if ("*Mac*OS*X*" iswm $1) {
		return "Mac OS X";
	}
	else if ("*Solaris*" iswm $1) {
		return "Solaris";
	}
	else if ("*Cisco*" iswm $1) {
		return "IOS";
	}
	else if ("*Printer*" iswm $1) {
		return "Printer";
	}
	else {
		return $1;
	}
}
