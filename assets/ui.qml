import bb.cascades 1.0
import bb.system 1.0

NavigationPane {
	id: navigationPane

	onCreationCompleted: {
		app.Refreshing.connect(function() {
			indicator.start();
		});

		app.DoneRefreshing.connect(function() {
			indicator.stop();
		});

		app.NewHeadline.connect(function(title, link, pubDate) {
			feedItems.insert({title: title, link: link, pubDate: pubDate});
		});

		app.Error.connect(function(msg) {
			errorDialog.body = msg;
			errorDialog.show();
		});

		app.refreshEach(parseInt(refreshSetting.text));
	}

	Menu.definition: MenuDefinition {
		settingsAction: SettingsActionItem {
			onTriggered: {
				navigationPane.push(settingsPage);
			}
		}
	}

	Page {
		Container {
			Container {
				layout: StackLayout {
					orientation: LayoutOrientation.LeftToRight
				}

				ActivityIndicator {
					id: indicator

					preferredHeight: 128
					preferredWidth: 128
					layoutProperties: StackLayoutProperties {
						spaceQuota: -1
					}
				}

				Label {
					text: "CBC"
					textStyle {
						base: SystemDefaults.TextStyles.BigText
					}

					preferredHeight: 128
					verticalAlignment: VerticalAlignment.Center
					layoutProperties: StackLayoutProperties {
						spaceQuota: 2
					}
				}
			}

			ListView {
				dataModel: GroupDataModel {
					id: feedItems

					sortedAscending: false
					grouping: ItemGrouping.None // TODO: I'd like to group by day only
					sortingKeys: ["pubDate"]
				}

				// Use a ListItemComponent to determine which property in the
				// data model is displayed for each list item
				listItemComponents: [
					ListItemComponent {
						type: "item"

						StandardListItem {
							title: ListItemData.title
							description: Qt.formatDateTime(ListItemData.pubDate)
						}
					}
				]

				onTriggered: {
					var selectedItem = dataModel.data(indexPath);
					invokeBrowser.query.uri = selectedItem.link;
					invokeBrowser.trigger("bb.action.OPEN");
				}

				attachedObjects: [
					Invocation {
						id: invokeBrowser

						query: InvokeQuery {
							uri: ""
						}
					}
				]
			}
		}
	}

	attachedObjects: [
		SystemDialog {
			id: errorDialog
			cancelButton.label: undefined
			title: "Error"
			body: ""
		},

		Page {
			id: settingsPage

			Container {
				layout: StackLayout {
					orientation: LayoutOrientation.LeftToRight
				}

				Label {
					text: "Refresh every "
				}

				TextField {
					id: refreshSetting
					inputMode: TextFieldInputMode.NumbersAndPunctuation
					text: "10"

					onTextChanged: {
						app.refreshEach(parseInt(refreshSetting.text));
					}
				}

				Label {
					text: " seconds"
				}
			}
		}
	]
}
