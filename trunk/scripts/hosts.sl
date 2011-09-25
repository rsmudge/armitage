import msf.*;

import javax.swing.*;
import javax.swing.event.*;

import java.awt.*;
import java.awt.event.*;

sub import_items {
	local('$description @imports');

	@imports = @(
		'Import and auto-detect file',
		'Acunetix XML',
		'Amap Log',
		'Amap Log -m',
		'Appscan XML',
		'Burp Session XML',
		'Foundstone XML',
		'IP360 ASPL',
		'IP360 XML v3',
		'Microsoft Baseline Security Analyzer',
		'Nessus NBE',
		'Nessus XML (v1 and v2)',
		'NetSparker XML',
		'NeXpose Simple XML',
		'NeXpose XML Report',
		'Nmap XML',
		'OpenVAS Report',
		'Qualys Asset XML',
		'Qualys Scan XML',
		'Retina XML'
	);

	foreach $description (@imports) {
		item($1, $description, $null, lambda(&importHosts, $command => "import_data"));
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
		writeb($handle, [$text getText] . "\n");
		closef($handle);

		importHosts("upload.hosts", $command => "import_ip_list");

		thread({		
			yield 8192;
			deleteFile("upload.hosts");
		});

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
		item($j, "Comprehensive", $null, createNmapFunction("-sS -sU -T5 -A -v -PE -PP -PS80,443 -PA3389 -PU40125 -PY -g 53"));

	enumerateMenu($1, $null);

	separator($1);

	item($1, "Clear Hosts", 'C', &clearHosts);
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
