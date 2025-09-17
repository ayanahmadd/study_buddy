//
//  ContentView.swift
//  studyBuddy
//
//  Created by Ayan Ahmad on 9/10/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack (alignment: .top) {
            Color.purple.opacity(0.4).edgesIgnoringSafeArea(.all)
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.5), Color.clear]), startPoint: .top, endPoint: .bottom)
                .frame(height:500)
                .edgesIgnoringSafeArea(.all)
            
            
            VStack(spacing: 20){
                HStack{
                    Text("Planner")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                    
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
