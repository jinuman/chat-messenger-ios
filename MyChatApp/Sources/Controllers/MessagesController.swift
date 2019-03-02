//
//  MessagesController.swift
//  MyChatApp
//
//  Created by Jinwoo Kim on 09/02/2019.
//  Copyright © 2019 jinuman. All rights reserved.
//

import UIKit
import Firebase

protocol MessagesControllerDelegate: class {
    func setNavBarTitle()
}

// Show user's messages view - Root
class MessagesController: UITableViewController {
    // MARK:- Properties for Messages Controller
    var messages: [Message] = []
    var messagesDictionary: [String: Message] = [:]
    let cellId = "MessagesCellId"
    fileprivate var timer: Timer?
    
    // MARK:- View controller life methods
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsSelection = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Logout", style: .plain,
                                                           target: self, action: #selector(handleLogout))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "new_message_icon"), style: .plain,
                                                            target: self, action: #selector(handleNewMessage))
        
        tableView.register(UserCell.self, forCellReuseIdentifier: cellId)
        checkIfUserIsLoggedIn()
        
        //        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showChatController))
        //        self.navigationController?.navigationBar.addGestureRecognizer(tapGesture)
    }

    // MARK:- Methods
    private func checkIfUserIsLoggedIn() {
        // if user is not logged in
        if Auth.auth().currentUser?.uid == nil {
            perform(#selector(handleLogout), with: nil, afterDelay: 0)
        } else {
            fetchUserAndSetupNavBarTitle()
        }
    }
    
    private func observeUserMessages() {
        guard let uid = Auth.auth().currentUser?.uid else {
            return
        }
        let reference = Database.database().reference()
        let userReference = reference.child("user-messages").child(uid)
        userReference.observe(.childAdded) { [weak self] (snapshot: DataSnapshot) in
            let chattedUserId = snapshot.key
            
            reference.child("user-messages").child(uid).child(chattedUserId).observe(.childAdded, with: { [weak self] (snapshot) in
                guard let self = self else {
                    return
                }
                let messageId = snapshot.key
                self.fetchMessage(with: messageId)
            })
        }
    }
    
    private func fetchMessage(with messageId: String) {
        let messagesReference = Database.database().reference().child("messages").child(messageId)
        messagesReference.observeSingleEvent(of: .value, with: { [weak self] (snapshot) in
            guard
                let self = self,
                let dictionary = snapshot.value as? [String: Any],
                let message = Message(dictionary: dictionary),
                let chatPartnerId = message.chatPartnerId() else {
                    return
            }
            self.messagesDictionary[chatPartnerId] = message
            self.attemptReloadOfTable()
        })
    }
    
    func attemptReloadOfTable() {
        // To fix bug: too much relaoding table into just reload table once.
        // Continuously cancel timer..and setup a new timer
        // Finally, no longer cancel the timer. -> Because timer is working with main thread run loop..? Almost right
        // So it fires block after 0.1 sec
        self.timer?.invalidate()
        //                print("canceled timer just before.")
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false, block: { [weak self] (timer: Timer) in
            guard let self = self else {
                return
            }
            self.messages = Array(self.messagesDictionary.values)
            self.messages.sort(by: { (message1, message2) -> Bool in
                if
                    let time1 = message1.timestamp,
                    let time2 = message2.timestamp {
                    return time1 > time2
                } else {
                    return false
                }
            })
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
                print("!! table view reloaded after 0.1 seconds")
            }
            
        })
        //                    print("Getting messages?")
    }
    
    @objc private func handleNewMessage() {
        let newMessageController = NewMessageController()
        newMessageController.delegate = self
        let navController = UINavigationController(rootViewController: newMessageController)
        present(navController, animated: true, completion: nil)
    }
    
    @objc func handleLogout() {
        do {
            try Auth.auth().signOut()
        } catch let logoutError {
            print(logoutError)
        }
        let loginController = LoginController()
        loginController.delegate = self
        present(loginController, animated: true, completion: nil)
    }
    
    // MARK:- Regarding tableView methods
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as? UserCell else {
            fatalError("Cell is not proper")
        }
        let message = messages[indexPath.row]
        cell.message = message
        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 84
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let message = messages[indexPath.row]
        guard let chatPartnerId = message.chatPartnerId() else {
            return
        }
        let ref = Database.database().reference().child("users").child(chatPartnerId)
        ref.observeSingleEvent(of: .value) { [weak self] (snapshot) in
            guard
                let self = self,
                let dictionary = snapshot.value as? [String: Any],
                let user = User(dictionary: dictionary) else {
                    return
            }
            user.id = chatPartnerId
            self.showChatController(for: user)
        }
    }
    
}


// MARK:- Regarding Custom LoginControllerDelegate
extension MessagesController: LoginControllerDelegate {
    func fetchUserAndSetupNavBarTitle() {
        guard let uid = Auth.auth().currentUser?.uid else {
            return
        }
        let ref = Database.database().reference()
        // observeSingleEvent : Once this value is returned..this callback no longer listening to any new values..
        ref.child("users").child(uid).observeSingleEvent(of: DataEventType.value) { [weak self] (snapshot: DataSnapshot) in
            guard
                let self = self,
                let dictionary = snapshot.value as? [String: Any] else {
                    return
            }
            self.navigationItem.title = dictionary["name"] as? String
            
            self.messages.removeAll()
            self.messagesDictionary.removeAll()
            
            self.tableView.reloadData()
            self.observeUserMessages() // 메인에 메세지들 불러오기
            //            self.setupNavBarWithUser(user: user)
        }
    }
    
    func setupNavBar(with name: String) {
        self.navigationItem.title = name
    }
    //    func setupNavBarWithUser(user: User) {
    //        let containerView = UIView()
    //
    //        let profileImageView = UIImageView()
    //        profileImageView.translatesAutoresizingMaskIntoConstraints = false
    //        profileImageView.contentMode = .scaleAspectFill
    //        profileImageView.layer.cornerRadius = 20
    //        profileImageView.clipsToBounds = true
    //        guard let urlString = user.profileImageUrl else {
    //            return
    //        }
    //        profileImageView.loadImageUsingCacheWithUrlString(urlString)
    //
    //        containerView.addSubview(profileImageView)
    //        // need x, y, width, height
    //        profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
    //        profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor).isActive = true
    //        profileImageView.widthAnchor.constraint(equalToConstant: 40).isActive = true
    //        profileImageView.heightAnchor.constraint(equalToConstant: 40).isActive = true
    //
    //        let nameLabel = UILabel()
    //        nameLabel.text = user.name
    //        nameLabel.translatesAutoresizingMaskIntoConstraints = false
    //
    //        containerView.addSubview(nameLabel)
    //        // need x, y, width, height
    //        nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 8).isActive = true
    //        nameLabel.centerYAnchor.constraint(equalTo: profileImageView.centerYAnchor).isActive = true
    //        nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true
    //        nameLabel.heightAnchor.constraint(equalTo: profileImageView.heightAnchor).isActive = true
    //
    //        self.navigationItem.titleView = containerView
    //    }
}

extension MessagesController: NewMessageControllerDelegate {
    @objc internal func showChatController(for user: User) {
        let chatLogController = ChatLogController(collectionViewLayout: UICollectionViewFlowLayout())
        chatLogController.user = user
        navigationController?.pushViewController(chatLogController, animated: true)
    }
}

