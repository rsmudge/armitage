#
# Screenshot viewer... whee?!?
#
import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;

import armitage.*;

global('%screenshots');
%screenshots = ohash();
setMissPolicy(%screenshots, {
	local('$panel $viewer $buttons $refresh $watch');

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

		$viewer = [new JLabel];
		[$panel add: [new JScrollPane: $viewer], [BorderLayout CENTER]];

		$buttons = [new JPanel];
		[$buttons setLayout: [new FlowLayout: [FlowLayout CENTER]]];
			$refresh = [new JButton: "Refresh"];
			[$refresh addActionListener: lambda({
				m_cmd($sid, "screenshot -v false");
			}, $sid => $2)];
			[$buttons add: $refresh];

			$watch = [new JButton: "Watch (10s)"];
			[$watch addActionListener: lambda({
				local('$timer');
				$timer = [new SimpleTimer: 10000];
				[$timer setRunnable: lambda({
					if ($sid !in %screenshots) {
						[$timer stop];
					}
					else {
						m_cmd($sid, "screenshot -v false");
					}
				}, \$sid, \$timer)];
			}, $sid => $2)];
			[$buttons add: $watch];
		[$panel add: $buttons, [BorderLayout SOUTH]];
	
	[$frame addTab: "Screenshot $2", $panel, lambda({ %screenshots[$key] = $null; size(%screenshots); }, $key => $2)];
	return $viewer;
});

%handlers["screenshot"] = {
	if ($0 eq "update" && $2 ismatch "Screenshot saved to: (.*?)") {
		local('$file $image $panel');
		($file) = matched();
		$image = [new ImageIcon: $file];

		[%screenshots[$1] setIcon: $image];

		if (-isFile $file && "*.jpeg" iswm $file) { 
			deleteFile($file);
		}
	}
};

sub createScreenshotViewer {
	return lambda({
		m_cmd($sid, "screenshot -v false");
	}, $sid => $1);
}
