import msf.*;

import javax.swing.*;
import javax.swing.event.*;

import java.awt.*;
import java.awt.event.*;

sub import_items {
	local('$command $description %imports');

	%imports = ohash(import_data => "Import and auto-detect file",
			import_amap_log => "THC-Amap scan results (-o)",
			import_amap_mlog => "THC-Amap scan results (-o -m)",
			import_ip_list => "List of line separated IPs",
			import_msfe_xml => "Metasploit Express Report (XML)",
			import_nessus_nbe => "Nessus scan results (NBE)",
			import_nessus_xml => "Nessus scan results (XML)",
			import_nessus_xml_v2 => "Nessus scan results (XML v2)",
			import_nexpose_simplexml => "Nexpose scan results (Simple XML)",
			import_nexpose_rawxml => "Nexpose scan results (Raw XML)",
			import_nmap_xml => "Nmap scan results (-oX)",
			import_qualys_xml => "Qualys scan results"
	);

	foreach $command => $description (%imports) {
		item($1, $description, $null, lambda(&importHosts, \$command));
	}
}

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
		local('$handle');
		$handle = openf(">upload.hosts");
		writeb($handle, [$text getText]);
		closef($handle);

		importHosts("upload.hosts", $command => "import_ip_list");
	
		deleteFile("upload.hosts");

		[$dialog setVisible: 0];
	}, \$text, \$dialog)];

	[$dialog add: $label, [BorderLayout NORTH]];
	[$dialog add: [new JScrollPane: $text], [BorderLayout CENTER]];
	[$dialog add: $finish, [BorderLayout SOUTH]];

	[$dialog setVisible: 1];
}

sub host_items {
	local('$i $j $k');
	$i = menu($1, "Import Hosts", 'I');
	import_items($i);

	item($1, "Add Hosts...", 'A', &addHostDialog);

	separator($1);

	$j = menu($1, "Nmap Scan", 'S');
		item($j, "Intense Scan", $null, createNmapFunction("-T5 -A -v"));
		item($j, "Intense Scan + UDP", $null, createNmapFunction("-sS -sU -T5 -A -v"));
		item($j, "Intense Scan, all TCP ports", $null, createNmapFunction("-p 1-65535 -T5 -A -v"));
		item($j, "Intense Scan, no ping", $null, createNmapFunction("-T5 -A -v -Pn"));
		item($j, "Ping Scan", $null, createNmapFunction("-T5 -sn"));
		item($j, "Quick Scan", $null, createNmapFunction("-T5 -F"));
		item($j, "Quick Scan (OS detect)", $null, createNmapFunction("-sV -T5 -O -F --version-light"));
		item($j, "Comprehensive", $null, createNmapFunction("-sS -sU -T5 -A -v -PE -PP -PS80,443 -PA3389 -PU40125 -PY -g 53 --script all"));

	enumerateMenu($1, $null);

	separator($1);

	item($1, "Clear Hosts", 'C', &clearHosts);
}

